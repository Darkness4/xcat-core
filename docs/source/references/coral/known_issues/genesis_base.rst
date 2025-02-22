xCAT Genesis Base
=================

xCAT ships a ``xCAT-genesis-base`` package as part of xcat-deps.  This is a light-weight diskless linux image based currently on Fedora28, that is used by xCAT to do hardware discovery.

To build your own version of the ``xCAT-genesis-base`` on-site using a server running OS other than Fedora28, like Red Hat Enterprise Linux 8, follow the steps below. Building ``xCAT-genesis-base`` on a server running Red Hat Enterprise Linux 7 or earlier, is no longer supported.

1. Download the latest timestamp version of the ``xCAT-genesis-builder`` RPM provided here: http://xcat.org/files/xcat/xcat-dep/2.x_Linux/beta/

2. Install the ``xCAT-genesis-builder`` RPM on a node installed with desired OS (currently verified with Fedora28 and Red Hat Enterprise Linux 8). For more details: https://github.com/xcat2/xcat-core/tree/master/xCAT-genesis-builder#readme 

3. Build the ``xCAT-genesis-base`` RPM: ::

    /opt/xcat/share/xcat/netboot/genesis/builder/buildrpm

To use the generated RPM from the step above for node discovery:

1. Install the generated ``xCAT-genesis-base`` RPM on the xCAT Management node 
2. Execute: ``mknb ppc64``

3. Follow :doc:`discover nodes </guides/admin-guides/manage_clusters/ppc64le/discovery/mtms/discovery.html>`

