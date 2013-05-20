#!/bin/sh
eval 'if [ -x /usr/local/cpanel/3rdparty/bin/perl ]; then exec /usr/local/cpanel/3rdparty/bin/perl -x -- $0 ${1+"$@"}; else exec /usr/bin/perl -x $0 ${1+"$@"}; fi;'
  if 0;

#!/usr/bin/perl
# Copyright(c) 2012 cPanel, Inc.
# All rights Reserved.
# copyright@cpanel.net
# http://cpanel.net
# Unauthorized copying is prohibited

# Tested on cPanel 11.30 - 11.38

# Maintainers: Charles Boyd, Anne Sipes, Paul Trost

use warnings;
use strict;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use File::HomeDir;
use Getopt::Long;


my $version = '1.2.1';

###################################################
# Check to see if the calling user is root or not #
###################################################
if ( $> != 0 ) {
    die "This script needs to be ran as the root user\n";
}

###########################################################
# Parse positional parameters for flags and set variables #
###########################################################

# Set defaults for positional parameters
my $noquery = 0;       # Default to doing DNS queries on user domains
my $nots    = 0;       # Default to displaying Tweak Settings Stats values
my $user    = undef;   # Default to no user to get system stats

GetOptions(
    'noquery' => \$noquery,
    'nots'    => \$nots,
    'user=s'  => \$user,    # =s is for --option with a value
);

# Going to be used later by IsBlocked();
my $blockedprog = 0;

###########################################
# Check if necessary programs are missing #
###########################################

if ( !-x '/usr/bin/dig' && $noquery == 0 ) {
    die "Dig is either missing or not executable, please fix or pass --noquery flag to bypass DNS lookups.\n";
}

#####################
# Open File Handles #
#####################

open( my $cpconfig_fh, '<', '/var/cpanel/cpanel.config' )
  or die "Could not open /var/cpanel/cpanel.config, $!\n";

open( my $statsconfig_fh, '<', '/etc/stats.conf' )
  if ( -f "/etc/stats.conf" );    # no die here as stats.conf may not exist

open( my $cpversion_fh, '<', '/usr/local/cpanel/version' )
  or die "Could not open /usr/local/cpanel/version, $!\n";

my ( $cpuser_fh, $cpuserstats_fh );
if ( defined($user) ) {
    open( $cpuser_fh, '<', "/var/cpanel/users/$user" )
      or die "Could not open /var/cpanel/users/$user, $!\n";

    my $homedir = File::HomeDir::users_home($user);
    if ( -f "$homedir/tmp/stats.conf" ) {
        open( $cpuserstats_fh, '<', "$homedir/tmp/stats.conf" )
          or die "Could not open '$homedir/tmp/stats.conf', $!\n";
    }
}

###################################
# Gather Values For Later Sub Use #
###################################

# If file handles are available, put the settings into hashes to use later

my %config_settings;
if ($cpconfig_fh) {
    while (<$cpconfig_fh>) {
        chomp( my $param = $_ );
        my ( $option, $value ) = split( '=', $param );
        if ( defined($value) ) {
            $config_settings{$option} = $value;
        }
    }
}

my %stats_settings;
if ($statsconfig_fh) {
    while (<$statsconfig_fh>) {
        chomp( my $param = $_ );
        my ( $option, $value ) = split( '=', $param );
        if ( defined($value) ) {
            $stats_settings{$option} = $value;
        }
    }
}

my %cpuser_settings;
if ($cpuser_fh) {
    while (<$cpuser_fh>) {
        chomp( my $param = $_ );
        my ( $option, $value ) = split( '=', $param );
        if ( defined($value) ) {
            $cpuser_settings{$option} = $value;
        }
    }
}

my %cpuser_stats_settings;
if ($cpuserstats_fh) {
    while (<$cpuserstats_fh>) {
        chomp( my $param = $_ );
        my ( $option, $value ) = split( '=', $param );
        if ( defined($value) ) {
            $cpuser_stats_settings{$option} = $value;
        }
    }
}

####################
# Main code output #
####################

# No arg = general info on web stats setup
if ( !defined($user) ) {
    print "\n";
    print "Available flags when running \"$0\" (if any):\n";
    print "    --user <cP user> (display stats configuration for a user)\n" if !defined($user);
    print "    --nots           (turns off display of Tweak Settings info)\n" if $nots == 0;
    print "\n";
    print "Displaying general information on web stats configuration.\n";
    print "\n";
    print DARK CYAN "[ Web Stats Probe v$version - Results For:", BOLD YELLOW " System ", DARK CYAN "]\n";
    print "\n";
    if ( !$nots ) {
        print "WHM TWEAK SETTINGS FOR STATS: \n";
        DisplayTS();
        print "\n";
    }
    print "CPANELLOGD: ",  LogDRunning(),  "\n";
    print "HTTPD CONF: ",  HttpdConf(),    "\n";
    print "BLACKED OUT: ", BlackedHours(), "\n";
    print "LOG PROCESSING RUNS EVERY: ", DARK GREEN LogsRunEvery(), " hours\n";
    print "BANDWIDTH PROCESSING RUNS EVERY: ", DARK GREEN BandwidthRunsEvery(), " hours\n";
    print "KEEPING UP: ", KeepingUp(), "\n";
    print "CAN ALL USERS PICK: ";
    print AllAllowed(), "\n";
    if ( AllAllowed() =~ 'No' ) {
        print "WHO CAN PICK STATS: ";
        print WhoCanPick(), "\n";
    }
    print "ANALOG: ",   IsAvailable('analog'),    " (Active by Default: ", IsDefaultOn('ANALOG'),    ")\n";
    print "AWSTATS: ",  IsAvailable('awstats'),   " (Active by Default: ", IsDefaultOn('AWSTATS'),   ")\n";
    print "WEBALIZER ", IsAvailable('webalizer'), " (Active by Default: ", IsDefaultOn('WEBALIZER'), ")\n";

    if ( CanRunLogaholic() eq 'Yes' ) {
        print "LOGAHOLIC: ", IsAvailable('logaholic'), " (Active by Default: ", IsDefaultOn('LOGAHOLIC'), ")\n";
    }
}
else {
    # If called with a user argument, let's verify that user exists and display
    # the output
    if ( -e $cpuser_fh and -d "/var/cpanel/userdata/$user" ) {
        print "\n";
        print "Available flags when running \"$0 --<cP user>\" (if any):\n";
            print "    --noquery (turns off DNS lookups for each user domain)\n" if $noquery == 0;
        print "\n";
        print DARK CYAN "[ Web Stats Probe v$version - Results For: ", BOLD YELLOW $user , DARK CYAN " ]\n";
        print "\n";

        # Here we want to test and see if STATGENS is present in the cPanel
        # user file. If it is this means that the server admin has blocked out
        # certain stats applications for the specific users in WHM. If STATGENS
        # exists then we test to see if there are any stats programs listed
        # after STATGENS=. If not then the admin has blocked all stats programs.
        # Yes, we have seen someone do this before.
        if ( defined( $cpuser_settings{'STATGENS'} )
                  and $cpuser_settings{'STATGENS'} eq "" ) {
            print BOLD RED "*** ALL STATS PROGRAMS BLOCKED FOR USER BY SERVER ADMIN IN WHM ***\n\n";
        }

        # If --noquery wasn't specified, then check if each of the user domains resolve to IP on the server
        if (!$noquery) {
            print "ALL DOMAINS RESOLVE TO SERVER: ";
            DomainResolves($user);
        }
        print "KEEPING UP (STATS): ", UserKeepUp($user), " (Last Run: ", LastRun($user), ")\n";
        print "KEEPING UP (BANDWIDTH): ", BwUserKeepUp($user), " (Last Run: ", BwLastRun($user), ")\n";
        if ( BwUserKeepUp($user) =~ 'No' ) {
            print "\n";
            print BOLD RED "*** Bandwidth processing isn't keeping up! Please check the eximstats DB for corruption ***\n";
            print "If the eximstats.sends table is corrupted then when runweblogs is ran the smtp rrd file won't generate correctly and the file /var/cpanel/lastrun/$user/bandwidth won't update.\n";
            print BOLD RED "*** Please run: \"mysqlcheck -r eximstats\" ***\n";
            print "\n";
        }
        print "ANALOG: ";
        print WillRunForUser( 'analog', $user );
        print "AWSTATS: ";
        print WillRunForUser( 'awstats', $user );
        print "WEBALIZER: ";
        print WillRunForUser( 'webalizer', $user );
        if ( CanRunLogaholic() =~ 'Yes' ) {
            print "LOGAHOLIC: ";
            print WillRunForUser( 'logaholic', $user );
        }
        if ( AllAllowed() =~ 'No' and UserAllowed($user) eq 'No' ) {
            print "CAN PICK STATS: ";
            print DARK GREEN "Yes\n" if UserAllowed($user) eq 'Yes';
            print BOLD RED "No\n"    if UserAllowed($user) eq 'No';
        }
        if ($blockedprog) {
            print "\n";
            print BOLD RED "*** Webstatsprobe reports that one or more statsprograms are BLOCKED for the user by the server admin ***\n";
            print BOLD RED "To correct this issue in WHM, go to:\n";
            print "Server Configuration >> Statistics Software Configuration >> User Permissions >>\n";
            print "Choose Users >> Choose Specific Stats Programs for\n";
            print "\n";
            print "To use the default setting of all apps available, remove the STATGENS line from the cPanel user file.\n";
        }
    }
    else {
        # Otherwise we say too bad so sad.
        print "\n";
        print "ERROR: User [ $user ] not found.\n";
        print "You may have entered the wrong username, or /var/cpanel/$user or /var/cpanel/userdata/$user is missing.\n";
        print "Usage: webstatsprobe <cP User>\n";
    }
}

print "\n";

#######################################
# Misc. checks for stupid user tricks #
#######################################

# Run the Awwwstats function to see if awstats.pl is executable
Awwwwstats();
CheckBadPerms();
print "\n";

###########
# Cleanup #
###########
close($cpconfig_fh);

# If there was no /etc/stats.conf, then no need to close the FH for it.
close($statsconfig_fh) if ( defined($statsconfig_fh) );
close($cpversion_fh);

# If $user wasn't supplied as an arg, then no need to close FHs for it..
close($cpuser_fh) if ( defined($user) );
close($cpuserstats_fh) if ( defined($user) and defined($cpuserstats_fh) );

##############
## Functions #
##############

sub BlackedHours {

    # Get the blackout hours and display if stats can run within those hours
    if ( $stats_settings{'BLACKHOURS'} ) {

        # Copy the blacked out hours into array @hours, splitting on ','
        my @hours = split( ',', $stats_settings{'BLACKHOURS'} );

        # Subtract the amount of array indices (hours) from 24 to get how many
        # hours are left that stats can run
        my $allowed = 24 - scalar(@hours);

        # if the amount of hours selected is 24, then stats will never run
        if ( scalar(@hours) == 24 ) {
            return "$stats_settings{'BLACKHOURS'}", "(Allowed time: ",
              BOLD RED "0 hours - STATS WILL NEVER RUN!", BOLD WHITE ")";
        }
        else {
            # If the amount of hours selected is 0, meaning no hours are blacked
            # out, then..
            if ( scalar(@hours) == 0 ) {
                return DARK GREEN "Never ",
                  BOLD WHITE "(Allowed Time: ", DARK GREEN "24 hours", BOLD WHITE ")";
            }
            else {
                # If some hours are blacked out, print the blacked out hours.
                return BOLD RED "$stats_settings{'BLACKHOURS'} ", BOLD WHITE "(Allowed Time: ", DARK GREEN "$allowed hours", BOLD WHITE ")";
            }
        }
    }
    else {
        # if /etc/stats.conf doesn't exist or does but BLACKHOURS not set, then
        # print "Never"
        return DARK GREEN "Never ", BOLD WHITE "(Allowed Time: ", DARK GREEN "24 hours", BOLD WHITE ")";
    }

}

sub LogsRunEvery {

 # Show how often stats are set to process, if value not set then return default
 # of 24.
    if ( $config_settings{'cycle_hours'} ) {
        return $config_settings{'cycle_hours'};
    }
    else {
        return 24;
    }

}

sub BandwidthRunsEvery {

    # Show how often bandwidth is set to process, if value not set then return
    # default of 2.
    if ( $config_settings{'bwcycle'} ) {
        return $config_settings{'bwcycle'};
    }
    else {
        return 2;
    }

}

sub IsAvailable {

 # See if the stats program is disabled in tweak settings, if so return Disabled
 # else return Available
    my $prog = shift;
    $prog = "skip" . $prog;

    if ( $config_settings{$prog} eq 1 or $config_settings{$prog} eq "" ) {
        return BOLD RED "Disabled";
    }
    else {
        return DARK GREEN "Available to Users";
    }

}

sub IsDefaultOn {

   # Make sure we're looking for the stats program in upper case, and display if
   # the stats program is set to to active by default or not
    my $prog = uc(shift);
    if (%stats_settings) {
        if ( !exists( $stats_settings{'DEFAULTGENS'} ) ) {
            # If no DEFAULTGENS in /etc/stats.conf
            return DARK GREEN "On";
        }
        else {
            if ( $stats_settings{'DEFAULTGENS'} !~ $prog ) {
                # Else it is there but the specific prog name isn't in the DEFAULTGENS line
                # This also takes into account DEFAULTGENS=0 which means all progs set to not active by default
                return BOLD RED "Off";
            }
            elsif ( $stats_settings{'DEFAULTGENS'} =~ $prog
                and IsAvailable( lc($prog) ) =~ 'Disabled' ) {
                   # Else, if the prog is in DEFAULTGENS (meaning it was set to Active by default,
                   # but the prog was then Disabled
                return BOLD RED "Off";
            }
            else {
                return DARK GREEN "On";
            }
        }
    }
    else {
        # Stats haven't been customized at all in WHM, so no stats.conf yet
        return DARK GREEN "On";
    }

}

sub AllAllowed {

    # Display if per WHM all users are allowed to pick stats programs
    if (%stats_settings) {
        if ( exists($stats_settings{'ALLOWALL'})
                and $stats_settings{'ALLOWALL'} eq 'yes' ) {
            return DARK GREEN "Yes";
        }
        elsif ( !$stats_settings{'ALLOWALL'}
            and !$stats_settings{'VALIDUSERS'} ) {
            # Else if ALLOWALL and
            # VALIDUSERS had no values
            return DARK GREEN "No";
        }
        else {
            # else if ALLOWALL is not equal to yes
            return BOLD RED "No";
        }
    }
    else {
        # If /etc/stats.conf doesn't exist
        return DARK GREEN "No";
    }

}

sub UserAllowed {

    # This UserAllowed function is called by the main body and is necessary to
    # output the warning for stats.conf. This function however is needed when
    # only yes/no output is required by other functions which call it such as
    # GetEnabledDoms().
    if (%stats_settings) {
        my $user = shift;
        if (    $stats_settings{'VALIDUSERS'}
            and $stats_settings{'VALIDUSERS'} =~ /\b$user\b/ ) {
            return "Yes";
        }
        else {
            # Else there are no users who can pick stat progs or supplied arg user
            # isn't in the list
            return "No";
        }
    }
    else {
        # Else if there are no users configured who can choose their own progs
        return "No";
    }

}

sub LogDRunning {

    # Check if cpanellogd is running. Null output from --check means it is.
    my $check = qx(/scripts/restartsrv_cpanellogd --check);

    if ( !$check ) {
        return DARK GREEN "Running";
    }
    else {
        return BOLD RED "Not Running";
    }

}

sub KeepingUp {

    # Find out if there is a stats file under /lastrun that is greater than the
    # (stats processing interval * 60 * 60), but only if that file is owned by a
    # current cPanel user
    my @outofdate;
    my $interval = LogsRunEvery() * 60 * 60;
    my $time     = time();
    my @filelist = glob '/var/cpanel/lastrun/*/stats';

    foreach my $file (@filelist) {
        my $mtime    = ( stat($file) )[9];
        my $duration = $time - $mtime;

        # now let's remove '/var/cpanel/lastrun', then '/stats/' so we can
        # get just the username
        my $user = $file;
        $user    =~ s/\/var\/cpanel\/lastrun\///;
        $user    =~ s/\/stats//;
        if ( $duration > $interval ) {
            if ( -d "/var/cpanel/userdata/$user" ) {
                my $olduser = qx(ls -la /var/cpanel/lastrun/$user/stats);
                push( @outofdate, $olduser );
            }
        }
    }

    if (@outofdate) {
        return BOLD RED "No", BOLD WHITE "Users out of date:\n",
          BOLD RED "@outofdate";
    }
    else {
        return DARK GREEN "Yes";
    }

}

sub UserKeepUp {

    # Display if the user's stats are being processed in time
    # $interval is running the return value of logsrunevery * 60 * 60 to get the
    # amount of seconds (default of 84400, or 24 hours)
    my $user     = shift;
    my $interval = LogsRunEvery() * 60 * 60;
    my $time     = time();
    my $file     = "/var/cpanel/lastrun/$user/stats";

    if ( -f $file ) {    # necessary as as file won't exist on a new user
        my $mtime    = ( stat($file) )[9];
        my $duration = $time - $mtime;
        if ( $duration > $interval ) {
            return BOLD RED "No";
        }
        else {
            return DARK GREEN "Yes";
        }
    }
    else {
        return BOLD RED "Hasn't processed yet";
    }

}

sub BwUserKeepUp {

    # Display if the user's stats are being processed in time
    # $interval is running the return value of logsrunevery * 60 to get the
    # amount of minutes (default of 120, or 2 hours)
    my $user     = shift;
    my $interval = BandwidthRunsEvery() * 60 * 60;
    my $time     = time();
    my $file     = "/var/cpanel/lastrun/$user/bandwidth";

    # Nessessary as file won't exist on a new user
    if ( -f $file ) {
        my $mtime    = ( stat($file) )[9];
        my $duration = $time - $mtime;
        if ( $duration > $interval ) {
            return BOLD RED "No";
        }
        else {
            return DARK GREEN "Yes";
        }
    }
    else {
        return BOLD RED "Hasn't been processed yet";
    }

}

sub LastRun {

    # Display when the user's stats were last ran
    my $user = shift;
    my $file = "/var/cpanel/lastrun/$user/stats";

    if ( -f $file ) {
        my $mtime = ( stat($file) )[9];
        $mtime = localtime($mtime);
        return DARK GREEN "$mtime";
    }
    else {
        return BOLD RED "Never";
    }

}

sub BwLastRun {

    # Display when the user's bandwidth processing was last ran
    my $user = shift;
    my $file = "/var/cpanel/lastrun/$user/bandwidth";

    if ( -f $file ) {
        my $mtime = ( stat($file) )[9];
        $mtime = localtime($mtime);
        return DARK GREEN $mtime;
    }
    else {
        return BOLD RED "Never";
    }

}

sub Awwwwstats {

    # Check to see if awstats.pl doesn't have correct permissions
    my $awstats = '/usr/local/cpanel/3rdparty/bin/awstats.pl';
    my $mode = sprintf '%04o', ( stat $awstats )[2] & 07777;

    if ( $mode ne '0755' ) {
        print "\n";
        print BOLD RED "AWStats Problem = Yes\n";
        print BOLD RED
          "/usr/local/cpanel/3rdparty/awstats.pl is not 755 permissions!\n";
    }
}

sub CheckBadPerms {
    
    if ( defined($statsconfig_fh) ) {
        my $mode = sprintf '%04o', ( stat $statsconfig_fh )[2] & 07777;
        if ( $mode ne '0644' ) {
            print BOLD RED "*** /etc/stats.conf doesn't have permissions of 644. If users have the ability to choose stat programs, this will cause the programs to be locked out by administrator in cPanel. ***\n";
        }
    }

}

sub HttpdConf {

    # No stats if Apache conf has problems, so check syntax
    my $check = qx(/usr/local/apache/bin/apachectl configtest 2>&1);

    if ( $check =~ 'Syntax OK' ) {
        return DARK GREEN "Syntax OK";
    }
    else {
        return BOLD RED "Syntax Errors ",
          BOLD WHITE "(Run: httpd configtest)\n\n",
          BOLD RED
"*** This means that Apache can't do a graceful restart and that the domlogs will be 0 bytes in size, so therefore no new stats will be processed until httpd.conf is fixed! ***\n";
    }

}

sub WhoCanPick {

    # Display users who have been specified to choose stats programs
    if (%stats_settings) {
        if ( $stats_settings{'VALIDUSERS'} ) {
            print DARK GREEN $stats_settings{'VALIDUSERS'};
        }
        else {
            # If there is no VALIDUSERS or it's false
            print DARK GREEN "Nobody";
        }
    }
    else {
        # If stats.conf doesn't exist yet, then no users can choose (default behavior)
        print DARK GREEN "Nobody";
    }
    return;

}

sub GetEnabledDoms {

    my $prog = uc(shift);
    my $user = shift;
    my @alldoms;
    my @domains;

    foreach my $param (%cpuser_settings) {
        if ( defined($param) and $param =~ /\ADNS/ ) {
            # If $param has a value and the line starts with DNS
            push( @alldoms, $cpuser_settings{$param} );
        }
    }

    # If $homedir/tmp/stats.conf exists then for each domain we want to see if
    # $prog-domainname eq yes or no
    if (%cpuser_stats_settings) {
        foreach my $dom (@alldoms) {
            my $capsdom = uc($dom);
            # $homedir/tmp/stats.conf contains the domain and it =yes (stats 
            # checked by user) or if a domain has been added but the domin list
            # in cPanel hasn't been re-saved yet then we display =yes,
            # otherwise =no.
            if ( ($cpuser_stats_settings{"$prog-$capsdom"} 
              and $cpuser_stats_settings{"$prog-$capsdom"} eq 'yes' )
             or ! $cpuser_stats_settings{"$prog-$capsdom"} ) {
                push( @domains, "$dom=yes" );
            }
            else {
                push( @domains, "$dom=no" );
            }
        }
        return @domains;
    }
    else {
        # If the user is new or just hasn't saved their log program choices in
        # cPanel, and the stats program is active by default, then show Yes for
        # each domain as the default then would be On since the user hasn't
        # overridden it in cPanel.
        if ( ( UserAllowed($user) =~ 'Yes' or AllAllowed =~ 'Yes' )
            and ( IsDefaultOn($prog) =~ 'On' ) ) {

            foreach my $dom (@alldoms) {
                $dom .= "=yes";
                push( @domains, $dom );
            }
            return @domains;
        }
        else {
            # If however the stats program is not active by
            # default then show No as stats won't generate for that program unless
            # the user specifically enables it in cPanel.
            my @domains;
            foreach my $dom (@alldoms) {
                $dom .= "=no";
                push( @domains, $dom );
            }
            return @domains;
        }
    }

}

sub DumpDomainConfig {
    
    my $prog = shift;
    my $user = shift;
    my @doms = GetEnabledDoms( $prog, $user );

    if ( !@doms ) {
        print BOLD RED "NO DOMAINS",
          BOLD WHITE " :: $prog is available but not active by default. $user ",
          DARK GREEN "DOES ",
          BOLD WHITE "have own privs to enable $prog for domains, but hasn't\n";
    }
    else {
        print DARK GREEN "CAN PICK ", BOLD WHITE "(Per-Domain Config Listed Below)\n";
        foreach my $dom (@doms) {
            my ( $domain, $enabled ) = split( '=', $dom );
            print "  $domain = ";
            if ( $enabled eq 'yes' ) {
                print DARK GREEN "$enabled", "\n";
            }
            elsif ( $enabled eq 'no' ) {
                print BOLD RED "$enabled", "\n";
            }
        }
    }

}

sub IsBlocked {

    my $prog = uc(shift);
    my $user = shift;

    # This first looks to see if STATGENS exists in the user file and STATGENS
    # does NOT contain $prog. # If $prog is not found then this means $prog is
    # blocked by the admin in WHM at: # Main >> Server Configuration >>
    # Statistics Software Configuration >> User Permissions >> Choose Users >>
    # Choose Specific Stats Programs for
    if (    $cpuser_settings{'STATGENS'}
        and $cpuser_settings{'STATGENS'} !~ $prog ) {

        $blockedprog = 1;
        return 'Blocked';
    }
    else {
        return "";
    }

}

sub WillRunForUser {
    my $prog = shift;
    my $user = shift;

    # If the stats prog is not set as available in WHM
    if ( IsAvailable($prog) =~ 'Disabled' ) {
        print BOLD RED "NO DOMAINS ", BOLD WHITE ":: $prog is disabled server wide\n";

        # if the stats prog is blocked by the admin
    }
    elsif ( IsBlocked( $prog, $user ) eq 'Blocked' ) {
        print BOLD RED "BLOCKED", BOLD WHITE ":: $prog is blocked by the administrator for this user\n";
    }
    else {
        # If the prog is off, then..
        if ( IsDefaultOn($prog) =~ 'Off' ) {

            # if the "Allow all users to change their web statistics generating
            # software." is off, then
            if ( AllAllowed =~ 'No' ) {

                # if the user is added to the list to choose progs, then
                if ( UserAllowed($user) =~ 'Yes' ) {
                    DumpDomainConfig( $prog, $user );
                }
                else {
                    # but if not, then print that prog is available but not
                    # active by default and user does not have privs to enable
                    # prog.
                    print BOLD RED "NO DOMAINS", BOLD WHITE " :: $prog is available, but not active by default\n";
                    print "\t", "$user ", BOLD RED "DOES NOT", BOLD WHITE " have privs to enable $prog for domains\n";
                }
            }
            else {
                # else, AllAllowed is yes, so show if prog is active or not for
                # each domain
                DumpDomainConfig( $prog, $user );
            }
        }
        else {
            # if the allow all users to change stats is yes OR the user is in
            # the allowed list, then show if prog is active or not for each
            # domain.
            if ( UserAllowed($user) =~ 'Yes' or AllAllowed() =~ 'Yes' ) {
                DumpDomainConfig( $prog, $user );
            }
            else {
                # else, print that prog is active by default for all domains as
                # the user has no ability to choose log progs
                print DARK GREEN "ALL DOMAINS", BOLD WHITE ":: $prog is enabled and active by default\n";
            }
        }
    }
    return;

}

sub CanRunLogaholic {

    # Check if cPanel is >= 11.31 (when Logaholic was added).
    while (<$cpversion_fh>) {
        my $version = $_;
        $version =~ s/\.//g;    # remove the periods to compare it lexically
        if ( $version ge '1131' ) {
            return "Yes";
        }
        else {
            return "No";
        }
    }
}

sub DomainResolves {

    # Check to see if user's domains resolve to IPs bound on the server.
    # This doesn't run if --noquery is used.
    my $user = shift;
    my $donotresolve;
    my $timedout;
    my $notbound;
    chomp( my $bound = qx(/sbin/ifconfig) );

    # Grab domain list from the cPanel user file
    my @domlist;
    while ( my ( $key, $value ) = each %cpuser_settings ) {
        if ( $key =~ /\ADNS/ ) {    # If $key line starts with DNS
            push( @domlist, $value );
        }
    }

    # For each domain in the list we see if google's resolver can resolve the IP
    foreach my $name (@domlist) {
        chomp( my $ip = qx(dig \@8.8.8.8 +short $name) );

        # If it can't be resolved..
        if ( $ip eq "" ) {
            $donotresolve .= "$name\n";
        }
        elsif ( $ip =~ 'connection timed out' ) {  # Else if the DNS lookup times out...
            $timedout .= "$name\n";
        }
        elsif ( $bound !~ $ip ) { # Else if the domain does resolve, just not to an IP on this server..
            $notbound .= "$name\n";
        }
    }

    # If $donotresolve and $notbound and $timedout are null, meaning all lookups
    # were successful
    if ( !$donotresolve and !$notbound and !$timedout ) {
        print DARK GREEN "Yes\n";
    }
    else {
        # Otherwise, if one or the other is not null..
        if ( $donotresolve or $notbound or $timedout ) {
            print BOLD RED "No\n";
        }
        if ($donotresolve) {
            print "The following domains do not resolve at all:\n";
            print BOLD RED "$donotresolve\n";
        }
        if ($timedout) {
            print "Lookups for the following domains timed out:\n";
            print BOLD RED "$timedout\n";
        }
        if ($notbound) {
            print "The following domains do not point to an IP bound on this server:\n";
            print BOLD RED "$notbound\n";
        }
    }

}

sub DisplayTS {

    print "Awstats reverse DNS resolution: ";
    # This setting defaults to Off
    if ( defined( $config_settings{'awstatsreversedns'} )
              and $config_settings{'awstatsreversedns'} == 1 )
    {
        print DARK GREEN "On\n";
    }
    else {
        print DARK GREEN "Off\n";
    }

    print "Allow users to update Awstats from cPanel: ";
    # This setting defaults to Off
    if ( defined($config_settings{'awstatsbrowserupdate'})
             and $config_settings{'awstatsbrowserupdate'} == 1 ) {
        print DARK GREEN "On\n";
    }
    else {
        print DARK GREEN "Off\n";
    }

    print "Delete each domain's access logs after stats run: ";
    # This setting defaults to On
    if ( defined($config_settings{'dumplogs'}) 
             and $config_settings{'dumplogs'} == 0 ) {
        print DARK GREEN "Off\n";
    }
    else {
        print DARK GREEN "On\n";
    }

    print "Extra CPUs for server load: ";
    # This setting defaults to 0
    if ( !defined($config_settings{'extracpus'}) ) {
        print DARK GREEN "0\n";
    }
    else {
        print DARK GREEN "$config_settings{'extracpus'}\n";
    }

}
