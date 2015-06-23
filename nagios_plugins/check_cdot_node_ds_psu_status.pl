#!/usr/bin/env perl

## File name : check_cdot_node_ds_psu_status.pl
## Describtion: script checks failed or not being present PSU(s) on NetApp cDOT node's disk shelves
##   
## Author:               sl0n <momonth@gmail.com>
## Version Number:       0.1
##
## Change History
## 23.06.2015 =>  CREATION/RELEASENOTE
##
## Dependencies:
## - NetApp SDK, see "use lib" paths below, change it to match your env accordingly
## 
## Script takes four arguments:
## - cDOT cluster management interface
## - cluster admin user name
## - cluster admin password
## - cluster node hostname
##
## Example: ./check_cdot_node_ds_psu_status.pl -H na201-mgmt.mydomain.com -u admin -p my_secret_passwd -n na201node-1a
##
## ToDO:
## - SSL cert based authentication against cluster management interface
## - run the script as user with a restricted set of privileges, ie not as 'admin'

use strict;
use lib '/usr/lib/perl5/vendor_perl/5.8.8/NetApp';
use lib "/usr/share/perl5/vendor_perl/NetApp";
use NaServer;
use Getopt::Long;

##############################################
###
### BEGIN MAIN
###
###############################################


my @vErrMessage = "";

main();

sub main() {

    my ($strCluster, $strNode, $strUser, $strPassword);
    GetOptions("H=s" => \$strCluster, 
	       "n=s" => \$strNode, 
	       "u=s" => \$strUser,
               "p=s" => \$strPassword);

    if (!$strCluster || !$strNode || !$strUser || !$strPassword) {
        print_usage();
        exit 3;
    } 

    # Connect via NetApp API

    my $socket = NaServer->new($strCluster, 1, 3);
    my $debug  = 0;

    $socket->set_style("LOGIN");
    $socket->set_transport_type("HTTPS");
    $socket->set_admin_user($strUser, $strPassword);


    # Fetching disk shelves info for a node
    my $vDiskShelvesInfo = $socket->invoke('storage-shelf-environment-list-info', "node-name", $strNode);

    if ($vDiskShelvesInfo->results_status() eq "failed")
    {
        printf ("API call failed: %s\n", $vDiskShelvesInfo->results_reason());
        exit 3;
    } else {

        my $vDiskShelfInfoList = $vDiskShelvesInfo->child_get("shelf-environ-channel-list");
	my @vDiskShelfInfoArray = $vDiskShelfInfoList->children_get();

	my $vChannel;
	foreach $vChannel (@vDiskShelfInfoArray) {
		
            # Fetching all disk shelves
            my $vEnvShelfList = $vChannel->child_get("shelf-environ-shelf-list");
	    my @vEnvShelfArray = $vEnvShelfList->children_get();

            # Looping across disk shelves
            my $vEnvShelfInfo;
            foreach $vEnvShelfInfo (@vEnvShelfArray) {
                my $vShelfID = $vEnvShelfInfo->child_get_string("shelf-id");
                my $vShelfSerialNo = $vEnvShelfInfo->child_get("sas-specific-info")->child_get_string("serial-no");

		#push (@vErrMessage, sprintf("DS-ID is $vShelfID\n"));

                # Fetching all PSUs on each disk shelf
                my $vPSUList = $vEnvShelfInfo->child_get("power-supply-list");
                my @vPSUArray = $vPSUList->children_get();

                my $vPSU;
                my $vPSUCount = 0;
		my $vPSUinErrorStateCount = 0;
                my $vPSUNumber = "";
                foreach $vPSU (@vPSUArray) {
                    my $vPSUSerialNo = $vPSU->child_get_string("power-supply-serial-no"); 
                    my $vPSUErrorState = $vPSU->child_get_string("power-supply-is-error"); 
                    $vPSUNumber = $vPSU->child_get_string("power-supply-element-number"); 

		    # Count of present PSUs
                    if ($vPSUSerialNo ne "") {
                        $vPSUCount += 1; 

                        # Count of PSUs being present, but in faulty state
			if ($vPSUErrorState ne "false") {
                            $vPSUinErrorStateCount += 1;
                            push (@vErrMessage, sprintf("DiskShelf ID $vShelfID (SerialNo $vShelfSerialNo) has broken PSU: position $vPSUNumber\n"));
                        }
                    }
                }

                # Error out if less than 2 PSUs being present
                if ($vPSUCount < 2 ) {
                    push (@vErrMessage, sprintf("DiskShelf ID $vShelfID (SerialNo $vShelfSerialNo) has less than 2 PSUs online\n"));
		}
            }

	    #push (@vErrMessage, sprintf("channel is $vChannelName"));
	}
    }

    unless ( $#vErrMessage ) {
        printf "DiskShelf PSU(s) status OK.\n";
        exit 0;
    } else {
	printf("@vErrMessage\n");
        exit 2;
    }
}

sub print_usage()
{
        print "\nUsage: $0 -H <cluster management interface> -u <admin_username> -p <admin_password> -n <node hostname>\n\n";
        print "<cluster management interface> - cluster management interface\n";
        print "<admin_username>               - cluster admin username\n";
        print "<admin_password>               - cluster admin password\n";
        print "<node hostname>                - cluster node name\n\n";
        print "eg: $0 -H na201-mgmt.mydomain.com -u admin -p my_secret_passwd -n na201node-1a\n\n";
}
