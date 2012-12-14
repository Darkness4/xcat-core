# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::ProfiledNodeUtils;

use strict;
use warnings;
use Socket;
use File::Path qw/mkpath/;
use File::Temp qw/tempfile/;
use Fcntl qw(:flock);
require xCAT::Table;
require xCAT::TableUtils;
require xCAT::NodeRange;
require xCAT::NetworkUtils;
require xCAT::DBobjUtils;


#--------------------------------------------------------------------------------

=head1    xCAT::ProfiledNodeUtils

=head2    Package Description

This program module file, is a set of node management utilities for Profile based nodes.

=cut

#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------

=head3 get_allocable_staticips_innet
      Description : Get allocable IPs from a network.
      Arguments   : $netname - network name
                    $exclude_ips_ref - excluded IPs list reference.
      Returns     : Reference of allocable IPs list
=cut

#-------------------------------------------------------------------------------
sub get_allocable_staticips_innet
{
    my $class = shift;
    my $netname = shift;
    my $exclude_ips_ref = shift;
    my %iphash;
    my @allocableips;

    foreach (@$exclude_ips_ref){
        $iphash{$_} = 0;
    }

    my $networkstab = xCAT::Table->new('networks');
    my $netentry = ($networkstab->getAllAttribsWhere("netname = '$netname'", 'ALL'))[0];
    my ($startip, $endip) =  split('-', $netentry->{'staticrange'});
    my $incremental = $netentry->{'staticrangeincrement'};
    my $validipsref;
    if ($incremental and $startip and $endip){
        $validipsref = xCAT::NetworkUtils->get_allips_in_range($startip, $endip, $incremental);
    }
    foreach (@$validipsref){
        if (! exists($iphash{$_})){
            push @allocableips, $_;
        }
    }
    return \@allocableips;
}

#-------------------------------------------------------------------------------

=head3 genhosts_with_numric_tmpl
      Description : Generate numric hostnames using numric template name.
      Arguments   : $format - The hostname format string..
                    $rank - The start number.
                    $amount - The total hostname number to be generated.
      Returns     : numric hostname list
      Example     : 
              calling  genhosts_with_numric_tmpl("compute#NNnode") will return a list like:
              ("compute00node", "compute01node", ..."compute98node", "compute99node")
=cut

#-------------------------------------------------------------------------------
sub genhosts_with_numric_tmpl
{
    my ($class, $format, $rank, $amount) = @_;

    my ($prefix, $appendix, $len) = xCAT::ProfiledNodeUtils->split_hostname($format, 'N');
    return xCAT::ProfiledNodeUtils->gen_numric_hostnames($prefix, $appendix, $len, $rank, $amount);
}

#-------------------------------------------------------------------------------

=head3 split_hostname
      Description : Split hostname format as prefix, appendix and number length.
      Arguments   : $format - hostname format
                    $patt_char - pattern char, we always use "N" to indicate numric pattern
      Returns     : ($prefix, $appendix, $numlen)
                    $prefix - the prefix string of hostname format.
                    $appendix - the appendix string of hostname format
                    $numlen - The number length in hostname format.
      Example     : 
              calling  split_hostname("compute#NNnode") will return a list like:
              ("compute", "node", 2)
=cut

#-------------------------------------------------------------------------------
sub split_hostname
{
    my ($class, $format, $patt_char) = @_;

    my $idx = index $format, "#$patt_char";
    my @array_format = split(//, $format);
    my $pos = $idx+2;
    while ( $pos <= (scalar(@array_format) - 1)){
        if ($array_format[$pos] eq "$patt_char"){
            $pos++;
        }else{
            last;
        }
    }
    my $ridx = $pos - 1;

    my $prefix = "";
    $prefix = substr $format, 0, $idx;
    my $appendix = "";
    if (($ridx + 1) != scalar(@array_format)){
        $appendix = substr $format, $ridx + 1;
    }
    return $prefix, $appendix, ($ridx - $idx);
}

#-------------------------------------------------------------------------------

=head3 gen_numric_hostnames
      Description : Generate numric hostnames.
      Arguments   : $prefix - The prefix string of the hostname.
                    $appendix - The appendix string of the hostname.
                    $len - the numric number length in hostname.
                    $rank - the start number for numric part
                    $amount - the amount of hostnames to be generated.
      Returns     : numric hostname list
      Example     : 
              calling  gen_numric_hostnames("compute", "node",2) will return a list like:
              ("compute00node", "compute01node", ..."compute98node", "compute99node")
=cut

#-------------------------------------------------------------------------------
sub gen_numric_hostnames
{
    my ($class, $prefix, $appendix, $len, $rank, $amount) = @_;
    my @hostnames;
    my $cnt = 0;

    if ($rank){
        $cnt = $rank;
    } 
    my $maxnum = 10 ** $len;
    while($cnt < $maxnum)
    {
        my $fullnum = $maxnum + $cnt;
        my $hostname = $prefix.(substr $fullnum, 1).$appendix;
        push (@hostnames, $hostname);
        if ($amount && (@hostnames == $amount)){
            last;
        }
        $cnt++;
    }
    return \@hostnames;
}

#-------------------------------------------------------------------------------

=head3 get_hostname_format_type
      Description : Get hostname format type.
      Arguments   : $format - hostname format
      Returns     : hostname format type value:
                    "numric" - numric hostname format.
                    "rack" - rack info hostname format.
      Example     : 
              calling  get_hostname_format_type("compute#NNnode") will return "numric"
              calling  get_hostname_format_type("compute-#RR-#NN") will return "rack" 
=cut

#-------------------------------------------------------------------------------
sub get_hostname_format_type{
    my ($class, $format) =  @_;
    my $type;
    my ($prefix, $appendix, $rlen, $nlen);

    my $ridx = index $format, "#R";
    my $nidx = index $format, "#N";
    if ($ridx >= 0){
        ($prefix, $appendix, $rlen) = xCAT::ProfiledNodeUtils->split_hostname($format, 'R');
        ($prefix, $appendix, $nlen) = xCAT::ProfiledNodeUtils->split_hostname($format, 'N');
        if ($rlen >= 10 || $nlen >= 10){
            $type = "unknown";
        } else{
            $type = "rack";
        }
    } elsif ($nidx >= 0){
        ($prefix, $appendix, $nlen) = xCAT::ProfiledNodeUtils->split_hostname($format, 'N');
        if ($nlen >= 10){
            $type = "unknown";
        } else{
            $type = "numric";
        }
    } else{
        $type = "unknown";
    }

    return $type;
}

#-------------------------------------------------------------------------------

=head3 rackformat_to_numricformat
      Description : convert rack hostname format into numric hostname format.
      Arguments   : $format - rack hostname format
                    $racknum - rack number.
      Returns     : numric hostname format.
      Example     : 
           calling  rackformat_to_numricformat("compute-#RR-#NN", 1) will return "compute-01-#NN" 
=cut

#-------------------------------------------------------------------------------
sub rackformat_to_numricformat{
    my ($class, $format, $rackname) = @_;
    my ($prefix, $appendix, $len) = xCAT::ProfiledNodeUtils->split_hostname($format, 'R');

    my %objhash = xCAT::DBobjUtils->getobjdefs({$rackname, "rack"});
    my $racknum = $objhash{$rackname}{"num"};
    my $maxnum = 10 ** $len;
    if ($racknum >= $maxnum ){
        return undef;
    }

    my $fullnum = $maxnum + $racknum;
    return $prefix.(substr $fullnum, 1).$appendix;
}

#-------------------------------------------------------------------------------

=head3 get_nodes_nic_attrs
      Description : Get nodes NIC attributes and return a dict.
      Arguments   : $nodelist - nodes list ref.
      Returns     : A hash ref of %nicsattrs for node's nics attributes.
                    keys of %nicsattrs are node names.
                    values of %nicsattrs are nics attrib ref.
                    For each nic attrib ref, the keys are nic names, like: ib0, eth0, bmc...
                    values are attributes of a specific nic, like:
                        type : nic type
                        hostnamesuffix: hostname suffix
                        customscript: custom script for this nic
                        network: network name for this nic
                        ip: ip address of this nic.
=cut

#-------------------------------------------------------------------------------
sub get_nodes_nic_attrs{
    my $class = shift;
    my $nodes = shift;

    my $nicstab = xCAT::Table->new( 'nics');
    my $entry = $nicstab->getNodesAttribs($nodes, ['nictypes', 'nichostnamesuffixes', 'niccustomscripts', 'nicnetworks']);

    my %nicsattrs;
    my @nicattrslist;

    foreach my $node (@$nodes){
        if ($entry->{$node}->[0]->{'nictypes'}){
            @nicattrslist = split(",", $entry->{$node}->[0]->{'nictypes'});
            foreach (@nicattrslist){
                my @nicattrs = split(":", $_);
                $nicsattrs{$node}{$nicattrs[0]}{'type'} = $nicattrs[1];
            }
        }

        if($entry->{$node}->[0]->{'nichostnamesuffixes'}){
            @nicattrslist = split(",", $entry->{$node}->[0]->{'nichostnamesuffixes'});
            foreach (@nicattrslist){
                my @nicattrs = split(":", $_);
                $nicsattrs{$node}{$nicattrs[0]}{'hostnamesuffix'} = $nicattrs[1];
            }
        }

        if($entry->{$node}->[0]->{'niccustomscripts'}){
            @nicattrslist = split(",", $entry->{$node}->[0]->{'niccustomscripts'});
            foreach (@nicattrslist){
                my @nicattrs = split(":", $_);
                $nicsattrs{$node}{$nicattrs[0]}{'customscript'} = $nicattrs[1];
            }
        }

        if($entry->{$node}->[0]->{'nicnetworks'}){
            @nicattrslist = split(",", $entry->{$node}->[0]->{'nicnetworks'});
            foreach (@nicattrslist){
                my @nicattrs = split(":", $_);
                $nicsattrs{$node}{$nicattrs[0]}{'network'} = $nicattrs[1];
            }
        }

        if($entry->{$node}->[0]->{'nicips'}){
            @nicattrslist = split(",", $entry->{$node}->[0]->{'nicips'});
            foreach (@nicattrslist){
                my @nicattrs = split(":", $_);
                $nicsattrs{$node}{$nicattrs[0]}{'ip'} = $nicattrs[1];
            }
        }
    }

    return \%nicsattrs;
}

#-------------------------------------------------------------------------------

=head3 get_netprofile_bmcnet
      Description : Get bmc network name of a network profile.
      Arguments   : $nettmpl - network profile name 
      Returns     : bmc network name of this network profile.
=cut

#-------------------------------------------------------------------------------
sub get_netprofile_bmcnet{
    my ($class, $netprofilename) = @_;

    my $netprofile_nicshash_ref = xCAT::ProfiledNodeUtils->get_nodes_nic_attrs($netprofilename)->{$netprofilename};
    my %netprofile_nicshash = %$netprofile_nicshash_ref;
    if (exists $netprofile_nicshash{'bmc'}{"network"}){
        return $netprofile_nicshash{'bmc'}{"network"}
    }else{
        return undef;
    }
}

#-------------------------------------------------------------------------------

=head3 get_netprofile_provisionnet
      Description : Get deployment network of a network profile.
      Arguments   : $nettmpl - network profile name 
      Returns     : deployment network name of this network profile.
=cut

#-------------------------------------------------------------------------------
sub get_netprofile_provisionnet{
    my ($class, $netprofilename) = @_;

    my $netprofile_nicshash_ref = xCAT::ProfiledNodeUtils->get_nodes_nic_attrs([$netprofilename])->{$netprofilename};
    my %netprofile_nicshash = %$netprofile_nicshash_ref;
    my $restab = xCAT::Table->new('noderes');
    my $installnicattr = $restab->getNodeAttribs($netprofilename, ['installnic']);
    my $installnic = $installnicattr->{'installnic'};

    if ($installnic){
        if (exists $netprofile_nicshash{$installnic}{"network"}){
            return $netprofile_nicshash{$installnic}{"network"}
        }
    }
    return undef;
}

#-------------------------------------------------------------------------------

=head3 get_output_filename
      Description : Generate a temp file name for placing output details for profiled node management operations.
                    We make this file generated under /install/ so that clients can access it through http.
      Arguments   : N/A
      Returns     : A temp filename placed under /install/pcm/work/
=cut

#-------------------------------------------------------------------------------
sub get_output_filename
{
    my $installdir = xCAT::TableUtils->getInstallDir();
    my $pcmworkdir = $installdir."/pcm/work/";
    if (! -d $pcmworkdir)
    {
        mkpath($pcmworkdir);
    }
    return tempfile("hostinfo_result_XXXXXXX", DIR=>$pcmworkdir);
}

#-------------------------------------------------------------------------------

=head3 get_all_chassis
      Description : Get all chassis in system.
      Arguments   : hashref: if not set, return a array ref.
                             if set, return a hash ref.
                    type   : "all", get all chassis, 
                             "cmm", get all chassis whose type is cmm
                    if type not specify, it is 'all'
      Returns     : ref for chassis list.
      Example     : 
                    my $arrayref = xCAT::ProfiledNodeUtils->get_all_chassis();
                    my $hashref = xCAT::ProfiledNodeUtils->get_all_chassis(1);
                    my $hashref = xCAT::ProfiledNodeUtils->get_all_chassis(1, 'cmm');
=cut

#-------------------------------------------------------------------------------
sub get_all_chassis
{
    my $class = shift;
    my $hashref = shift;
    my $type = shift;
    my %chassishash;
    my %chassistype = ('all' => '__Chassis', 'cmm' => '__Chassis_IBM_Flex_chassis');

    if (not $type) {
        $type = 'all';
    }
    my @chassis = xCAT::NodeRange::noderange($chassistype{$type});
    if ($hashref){
        foreach (@chassis){
            $chassishash{$_} = 1;
        }
        return \%chassishash;
    } else{
        return \@chassis;
    }
}

#-------------------------------------------------------------------------------

=head3 get_all_rack
      Description : Get all rack in system.
      Arguments   : hashref: if not set, return a array ref.
                             if set, return a hash ref.
      Returns     : ref for rack list.
      Example     : 
                    my $arrayref = xCAT::ProfiledNodeUtils->get_all_rack();
                    my $hashref = xCAT::ProfiledNodeUtils->get_all_rack(1);
=cut

#-------------------------------------------------------------------------------
sub get_all_rack
{
    my $class = shift;
    my $hashref = shift;
    my %rackhash = ();
    my @racklist = ();

    my $racktab = xCAT::Table->new('rack');
    my @racks = $racktab->getAllAttribs(('rackname'));
    foreach (@racks){
        if($_->{'rackname'}){
            if ($hashref){
                $rackhash{$_->{'rackname'}} = 1;
            }else {
                push @racklist, $_->{'rackname'};
            }
        }
    }
   
    if ($hashref){
        return \%rackhash;
    }else{
        return \@racklist;
    }
}

#-------------------------------------------------------------------------------

=head3 get_racks_for_chassises
      Description : Get rack info for a chassis list.
      Arguments   : $chassislistref - chassis list reference.
      Returns     : A dict ref. keys are chassis name, values are rack name for each chassis.
=cut

#-------------------------------------------------------------------------------
sub get_racks_for_chassises
{
    my $class = shift;
    my $chassislistref = shift;
    my %rackinfodict = ();

    my $nodepostab = xCAT::Table->new('nodepos');
    my $racksref = $nodepostab->getNodesAttribs($chassislistref, ['rack']);
    foreach (@$chassislistref){
        $rackinfodict{$_} = $racksref->{$_}->[0]->{'rack'};
    }
    return \%rackinfodict;
}

#-------------------------------------------------------------------------------

=head3 get_allnode_singleattrib_hash
      Description : Get all records of a column from a table, then return a hash.
                    The return hash's keys are the records of this attribute 
                    and values are all set as 1.
      Arguments   : $tabname - the table name.
                    $attr - the attribute name.
      Returns     : Reference of the records hash.
=cut

#-------------------------------------------------------------------------------
sub get_allnode_singleattrib_hash
{
    my $class = shift;
    my $tabname = shift;
    my $attr = shift;
    my $table = xCAT::Table->new($tabname);
    my @entries = $table->getAllNodeAttribs([$attr]);
    my %allrecords;
    foreach (@entries) {
        if ($_->{$attr}){
            $allrecords{$_->{$attr}} = 0;
        }
    }
    return \%allrecords;
}

#-------------------------------------------------------------------------------

=head3 is_discover_started
      Description : Judge whether profiled nodes discovering is running or not.
      Arguments   : NA
      Returns     : 1 - Discover is running
                    0 - Discover is not started.
=cut

#-------------------------------------------------------------------------------
sub is_discover_started
{
    my @sitevalues = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if (! $sitevalues[0]){
        return 0;
    }
    return 1;
}

#-------------------------------------------------------------------------------

=head3 get_node_profiles
      Description : Get nodelist's profile and return a hash ref.
      Arguments   : node list.
      Returns     : nodelist's profile hash.
                    keys are node names.
                    values are hash ref. This hash ref is placing the node's profile information:
                        keys can be followings: "NetworkProfile", "ImageProfile", "HardwareProfile"
                        values are the profile names.
=cut

#-------------------------------------------------------------------------------

sub get_nodes_profiles
{
    my $class = shift;
    my $nodelistref = shift;
    my %profile_dict;

    my $nodelisttab = xCAT::Table->new('nodelist');
    my $groupshashref = $nodelisttab->getNodesAttribs($nodelistref, ['groups']);
    my %groupshash = %$groupshashref;

    foreach (keys %groupshash){
        my $value = $groupshash{$_};
        my $groups = $value->[0]->{'groups'};
        # groups looks like "__Managed,__NetworkProfile_default_cn,__ImageProfile_rhels6.3-x86_64-install-compute"
        my @grouplist = split(',', $groups);
        my @profilelist = ("NetworkProfile", "ImageProfile", "HardwareProfile");
        foreach my $group (@grouplist){
            foreach my $profile (@profilelist){
                my $idx = index ($group, $profile);
                # The Group starts with __, so index will be 2.
                if ( $idx == 2 ){
                    # The group string will like @NetworkProfile_<profile name>
                    # So, index should +3, 2 for '__', 1 for _.
                    my $append_index = length($profile) + 3;
                    $profile_dict{$_}{$profile} = substr $group, $append_index;
                    last;
                }
            }
        }
    }
    return \%profile_dict;
}

#-------------------------------------------------------------------------------

=head3 get_imageprofile_prov_method
      Description : Get A node's provisioning method from its imageprofile attribute.
      Arguments   : $imgprofilename - imageprofile name
      Returns     : node's provisioning method: install, netboot...etc
=cut

#-------------------------------------------------------------------------------
sub get_imageprofile_prov_method
{

    # For imageprofile, we can get node's provisioning method through:
    # nodetype table: node (imageprofile name), provmethod (osimage name)
    # osimage table: imagename (osimage name), provmethod (node deploy method: install, netboot...)
    my $class = shift;
    my $imgprofilename = shift;

    my $nodetypestab = xCAT::Table->new('nodetype');
    my $entry = ($nodetypestab->getAllAttribsWhere("node = '$imgprofilename'", 'ALL' ))[0];
    my $osimgname = $entry->{'provmethod'};

    #my $osimgtab = xCAT::Table->new('osimage');
    #my $osimgentry = ($osimgtab->getAllAttribsWhere("imagename = '$osimgname'", 'ALL' ))[0];
    #return $osimgentry->{'provmethod'};
}

#-------------------------------------------------------------------------------

=head3 check_profile_consistent
      Description : Check if three profile consistent
      Arguments   : $imageprofile - image profile name
                    $networkprofile - network profile name
                    $hardwareprofile - harware profile name
      Returns     : returncode, errmsg - consistent
                    returncode=1 - consistent
                    returncode=0 - not consistent
=cut

#-------------------------------------------------------------------------------
sub check_profile_consistent{
    my $class = shift;
    my $imageprofile = shift;
    my $networkprofile = shift;
    my $hardwareprofile = shift;
    
    # Check the profiles are existing in DB.
    my @nodegrps = xCAT::TableUtils->list_all_node_groups();
    unless(grep{ $_ eq $imageprofile} @nodegrps){
        return 0, "Image profile not defined in DB."
    }
    unless(grep{ $_ eq $networkprofile} @nodegrps){
        return 0, "Network profile not defined in DB."
    }
    if ($hardwareprofile){
        unless(grep{ $_ eq $hardwareprofile} @nodegrps){
            return 0, "Hardware profile not defined in DB."
        }
    }

    # Profile consistent keys, arch=>netboot,  mgt=>nictype
    my %profile_dict = ('x86' => 'xnba','x86_64' => 'xnba', 'ppc64' => 'yaboot',
                        'fsp' => 'FSP', 'ipmi' => 'BMC');
                        
    # Get Imageprofile arch
    my $nodetypetab = xCAT::Table->new('nodetype');
    my $nodetypeentry = $nodetypetab->getNodeAttribs($imageprofile, ['arch']);
    my $arch = $nodetypeentry->{'arch'};
    $nodetypetab->close();
    
    # Get networkprofile netboot and installnic
    my $noderestab = xCAT::Table->new('noderes');
    my $noderesentry = $noderestab->getNodeAttribs($networkprofile, ['netboot', 'installnic']);
    my $netboot = $noderesentry->{'netboot'};
    my $installnic = $noderesentry->{'installnic'}; 
    $noderestab->close();
    
    # Get networkprofile nictypes
    my $netprofile_nicshash_ref = xCAT::ProfiledNodeUtils->get_nodes_nic_attrs([$networkprofile])->{$networkprofile};
    my %netprofile_nicshash = %$netprofile_nicshash_ref;
    my $nictype = undef;
    foreach (keys %netprofile_nicshash) {
        my $value = $netprofile_nicshash{$_}{'type'};
        if (($value eq 'FSP') or ($value eq 'BMC')) {
            $nictype = $value;
        }
    }
    
    #Get hardwareprofile mgt
    my $nodehmtab = xCAT::Table->new('nodehm');
    my $mgtentry = $nodehmtab->getNodeAttribs($hardwareprofile, ['mgt']);  
    my $mgt = undef;
    $mgt = $mgtentry->{'mgt'} if ($mgtentry->{'mgt'});
    $nodehmtab->close();
    
    # Check if exists provision network
    if (not ($installnic and exists $netprofile_nicshash{$installnic}{"network"})){
        return 0, "Provisioning network not defined for network profile."
    }

    # Check if imageprofile is consistent with networkprofile
    if ($profile_dict{$arch} ne $netboot) {
        return 0, "Imageprofile's arch is not consistent with networkprofile's netboot."
    }
    
    # Check if networkprofile is consistent with hardwareprofile
    if (not $hardwareprofile) { # Not define hardwareprofile
        if (not $nictype) {  # Networkprofile is not fsp or bmc
            return 1, "";
        }elsif ($nictype eq 'FSP' or $nictype eq 'BMC') {
            return 0, "$nictype networkprofile must use with hardwareprofile.";
        }
    }
        
    if (not $nictype and $mgt) { 
        # define hardwareprofile, not define fsp or bmc networkprofile
        return 0, "$profile_dict{$mgt} hardwareprofile must use with $profile_dict{$mgt} networkprofile.";
    }
    
    if ($profile_dict{$mgt} ne $nictype) {
        # Networkprofile's nictype is not consistent with hadrwareprofile's mgt
        return 0, "Networkprofile's nictype is not consistent with hardwareprofile's mgt.";
    }
    
    return 1, "";
}

#-------------------------------------------------------------------------------

=head3 is_fsp_node
      Description : Judge whether nodes use fsp.
      Arguments   : $node - node name
      Returns     : 1 - Use fsp
                    0 - Not use fsp
=cut

#-------------------------------------------------------------------------------
sub is_fsp_node
{
    my $class = shift;
    my $node = shift;
    my $nicstab = xCAT::Table->new('nics');
    my $entry = $nicstab->getNodeAttribs($node, ['nictypes']);
    $nicstab->close();
 
    if ($entry->{'nictypes'}){
        my @nicattrslist = split(",", $entry->{'nictypes'});
        foreach (@nicattrslist){
            my @nicattrs = split(":", $_);
            if ($nicattrs[1] eq 'FSP'){
                return 1;
            }
        }
    }

    return 0;
}

#-------------------------------------------------------------------------------

=head3 get_nodes_cmm
      Description : Get the CMM of nodelist 
      Arguments   : $nodelist - the ref of node list array
      Returns     : $cmm - the ref of hash like
                    {
                      "cmm1" => 1,
                      "cmm2" => 1                          
                    }
=cut

#-------------------------------------------------------------------------------
sub get_nodes_cmm
{
    my $class = shift;
    my $nodelistref = shift;
    my @nodes = @$nodelistref;
    my %returncmm;
    
    my $mptab = xCAT::Table->new('mp');
    my $entry = $mptab->getNodesAttribs($nodelistref, ['mpa']);
    $mptab->close();
    
    foreach (@nodes) {
        my $mpa = $entry->{$_}->[0]->{'mpa'};
        if ($mpa and not exists $returncmm{$mpa}){
            $returncmm{$mpa} = 1;
        }
    }
    
    return \%returncmm
}
