#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::FSPUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
        use lib "/usr/opt/perl5/lib/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/5.8.2";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2";
}

use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
use POSIX qw(ceil);
use File::Path;
use Socket;
use strict;
use Symbol;
use IPC::Open3;
use warnings "all";
require xCAT::InstUtils;
require xCAT::NetworkUtils;
require xCAT::Schema;
require xCAT::Utils;
use  Data::Dumper;
require xCAT::NodeRange;
require DBI;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(genpassword runcmd3);

my $utildata; #data to persist locally


#-------------------------------------------------------------------------------

=head3  fsp_api_action
    Description:
        invoke the fsp_api to perform the functions 

    Arguments:
        $node_name: 
        $attrs: an attributes hash 
	$action: the operations on the fsp, bpa or lpar
	$tooltype: 0 for HMC, 1 for HNM
    Returns:
        Return result of the operation
    Globals:
        none
    Error:
        none
    Example:
        my $res = xCAT::FSPUtils::fsp_api_action( $node_name, $d, "add_connection", $tooltype );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_api_action {
    my $node_name  = shift;
    my $attrs      = shift;
    my $action     = shift;
    my $tooltype   = shift;
    my $parameter   = shift;
#    my $user 	   = "HMC";
#    my $password   = "abc123";
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api"; 
    my $id         = 1;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
    my $res;    
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }

    $id = $$attrs[0];
    $fsp_name = $$attrs[3]; 

    if($$attrs[4] =~ /^fsp$/ || $$attrs[4] =~ /^lpar$/ || $$attrs[4] =~ /^cec$/) {
        $type = 0;
    } elsif($$attrs[4] =~ /^bpa$/ || $$attrs[4] =~ /^frame$/) { 
	    $type = 1;
    } else { 
        $res = "$fsp_name\'s type is $$attrs[4]. Not support for $$attrs[4]";
	    return ([$node_name, $res, -1]);
    } 

    if( $action =~ /^add_connection$/) { 
        ############################
        # Get IP address
        ############################
        $fsp_ip = xCAT::Utils::getNodeIPaddress( $fsp_name, $parameter );
	    undef($parameter);
    } else {
        $fsp_ip = xCAT::Utils::getNodeIPaddress( $fsp_name );
    }

    if(!defined($fsp_ip)) {
        $res = "Failed to get the $fsp_name\'s or the related FSPs/BPAs' ip";
        return ([$node_name, $res, -1]);	
    }

    if($fsp_ip eq "-1") {
        $res = "Cannot open vpd table";
        return ([$node_name, $res, -1]);	
	} elsif( $fsp_ip eq "-3") {
        $res = "It doesn't have the  FSPs or BPAs whose side is the value as specified or by default.";
        return ([$node_name, $res, -1]);	
	}

    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
    
    my $cmd;
    my $install_dir = xCAT::Utils->getInstallDir();
    if( $action =~ /^code_update$/) { 
        $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name: -d $install_dir/packages_fw/";
    } elsif($action =~ /^add_connection$/) {
        my $ppcdirecttab = xCAT::Table->new( 'ppcdirect');
        if ( ! $ppcdirecttab) {
            $res = "Failed to open table 'ppcdirect'.";	
	        return ([$node_name, $res, -1]);
     	}	
     	my $password_hash    = $ppcdirecttab->getAttribs({'hcp'=> $fsp_name,'username'=>"HMC" } ,[qw(password)]);
        $ppcdirecttab->close();
        my $user = "HMC";
        my $password = $password_hash->{password};
    	$cmd = "$fsp_api -a $action -u $user -p $password -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    } else {
        if( defined($parameter) ) {
            $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:$parameter";
        } else {
            $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
        }
    }

    #print "cmd: $cmd\n"; 
    $SIG{CHLD} = 'DEFAULT'; 
    $res = xCAT::Utils->runcmd($cmd, -1);
    #$res = "good"; 
    $Rc = $::RUNCMD_RC;
    #$Rc = -1;
    ##################
    # output the prompt
    #################
    #$outhash{ $node_name } = $res;
    if(defined($res)) {
        $res =~ s/$node_name: //;
    }
    return( [$node_name,$res, $Rc] ); 
}

#-------------------------------------------------------------------------------

=head3  fsp_state_action
    Description:
        invoke the fsp_api to perform the functions(all_lpars_state) 

    Arguments:
        $node_name: 
        $attrs: an attributes hash 
	$action: the operations on the fsp, bpa or lpar
	$tooltype: 0 for HMC, 1 for HNM
    Returns:
        Return result of the operation
    Globals:
        none
    Error:
        none
    Example:
        my $res = xCAT::FSPUtils::fsp_state_action( $cec_bpa, $type, $action, $tooltype );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_state_action {
    my $node_name  = shift;
    my $type_name  = shift;
    my $action     = shift;
    my $tooltype   = shift;
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api"; 
    my $id         = 0;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
    my @res;    
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }

    $fsp_name = $node_name; 

     
    if($type_name =~ /^fsp$/ || $type_name =~ /^lpar$/ || $type_name =~ /^cec$/) {
        $type = 0;
    } else { 
	$type = 1;
    } 

    ############################
    # Get IP address
    ############################
    $fsp_ip = xCAT::Utils::getNodeIPaddress( $fsp_name );
    if(!defined($fsp_ip)) {
        $res[0] = ["Failed to get the $fsp_name\'s ip"];
        return ([-1, @res]);	
    }
	
    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
    my $cmd;
    #$cmd = "$fsp_api -a $action -u $user -p $password -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    $SIG{CHLD} = 'DEFAULT'; 
    @res = xCAT::Utils->runcmd($cmd, -1);
    #$res = "good"; 
    $Rc = $::RUNCMD_RC;
    #$Rc = -1;
    ##################
    # output the prompt
    #################
    #$outhash{ $node_name } = $res;
    if( @res ) {
        $res[0] =~ s/$node_name: //;
    }
    return( [$Rc,@res] ); 
}

sub getTypeOfNode
{
    my $class      = shift;
    my $node        = shift;
    my $callback   = shift;
    
    my $nodetypetab = xCAT::Table->new( 'nodetype');

    if (!$nodetypetab) {
        my $rsp;
        $rsp->{errorcode}->[0] = [1];
        $rsp->{data}->[0]= "Failed to open table 'nodetype'";
        xCAT::MsgUtils->message('E', $rsp, $callback);
    }
    my $nodetype_hash    = $nodetypetab->getNodeAttribs( $node,[qw(nodetype)]);
    my $nodetype    = $nodetype_hash->{nodetype};
    if ( !$nodetype) {
        my $rsp;
        $rsp->{errorcode}->[0] = [1];
        $rsp->{data}->[0]= "Not found the $node\'s nodetype";
        xCAT::MsgUtils->message('E', $rsp, $callback);
        return undef;
    }
    return $nodetype;    
    
}


#-------------------------------------------------------------------------------

=head3  fsp_api_partition_action
    Description:
        invoke the fsp_api to perform the functions 

    Arguments:
        $node_name: 
        $attrs: an attributes hash 
	$action: the operations on the fsp, bpa or lpar
	$tooltype: 0 for HMC, 1 for HNM
    Returns:
        Return result of the operation
    Globals:
        none
    Error:
        none
    Example:
        my $res = xCAT::FSPUtils::fsp_api_action( $node_name, $d, "add_connection", $tooltype );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_api_create_parttion {
    my $starting_lpar_id   = shift;
    my $octant_conf_value  = shift;
    my $node_number        = shift;
    my $attrs      = shift;
    my $action     = shift;
    my $tooltype   = shift;
#    my $user 	   = "HMC";
#    my $password   = "abc123";
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api"; 
    my $id         = 0;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
    my $res;    
    my $number_of_lpars_per_octant;
    my $octant_num_needed;
    my $starting_octant_id;
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }
   
    use Data::Dumper; 
    print Dumper($attrs);
    $fsp_name = $$attrs[3]; 
    $type = 0;

    ############################
    # Get IP address
    ############################
    $fsp_ip = xCAT::Utils::getNodeIPaddress( $fsp_name );
    if(!defined($fsp_ip)) {
        $res = "Failed to get the $fsp_name\'s ip";
        return ([$fsp_name, $res, -1]);	
    }
	
    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
   
    #octant configuration values could be 1,2,3,4,5 ; AS following:
    #  1 - 1 partition with all cpus and memory of the octant
    #  2 - 2 partitions with a 50/50 split of cpus and memory
    #  3 - 3 partitions with a 25/25/50 split of cpus and memory
    #  4 - 4 partitions with a 25/25/25/25 split of cpus and memory
    #  5 - 2 partitions with a 25/75 split of cpus and memory
    if($octant_conf_value  ==  1)  {
	$number_of_lpars_per_octant  = 1;
    } elsif($octant_conf_value  ==  2 ) {
        $number_of_lpars_per_octant  = 2;
    } elsif($octant_conf_value  ==  3 ) {
        $number_of_lpars_per_octant  = 3;
    } elsif($octant_conf_value  ==  4 ) {
        $number_of_lpars_per_octant  = 4;
    } elsif($octant_conf_value  ==  5 ) {
        $number_of_lpars_per_octant  = 2;
    } else {
        $res = "Wrong octant configuration values!\n";
	return ([$fsp_name, $res, -1]);
    }	    
   
    $octant_num_needed = $node_number/$number_of_lpars_per_octant;
    $starting_octant_id = int($starting_lpar_id/4);

    print "$octant_num_needed\n";
    if(7 - $starting_octant_id < $octant_num_needed ) {
        $res =  "starting LPAR id is $starting_lpar_id, starting octant id is $starting_octant_id, octant configuration values is $octant_conf_value. Wrong plan.\n";
        return ([$fsp_name, $res, -1]);  
    }
   
    my $new_pending_pump_mode = 1;
    my $parameters = "$new_pending_pump_mode:$octant_num_needed";
    my $octant_id = $starting_octant_id ;
    my $new_pending_interleave_mode = 2;
    my $i = 0;
    for($i = 0; $i < $octant_num_needed; $i++  ) {
        $octant_id += $i;
	$parameters = $parameters.":$octant_id:$octant_conf_value:$new_pending_interleave_mode";
    }

    my $cmd;
    $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:0:$fsp_name:$parameters";
    #fsp-api -a set_octant_cfg -t 0:40.7.5.1:0:M019:1:1:7:4:2
    #print "cmd: $cmd\n"; 
    $SIG{CHLD} = 'DEFAULT'; 
    $res = xCAT::Utils->runcmd($cmd, -1);
    #$res = "good"; 
    $Rc = $::RUNCMD_RC;
    print $cmd;
    #$Rc = -1;
    ##################
    # output the prompt
    #################
    #$outhash{ $node_name } = $res;
    if( defined($res) ) {
        $res =~ s/$fsp_name: //;
    }
    return( [$fsp_name,$res, $Rc] ); 
}






1;
