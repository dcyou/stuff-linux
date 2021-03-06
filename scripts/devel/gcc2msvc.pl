#!/usr/bin/perl

#GCC filter script
#Converts GCC error messages into a format compatible with Visual Studio
#This file is provided "as is" under the BSD license

#To debug binaries produced by GCC with Visual Studio debugger, try VisualGDB:
#                         http://visualgdb.com/

use strict;

my %MOUNTS;
my $ROOTMOUNT;
my $WD;
my $unix2winpath;

sub check_mounts
{
    my $fp = $_[0];

    foreach(keys %MOUNTS)
    {
        if ($fp =~ /^$_\/(.*)$/)
        {
            my $suffix = $1;
            $suffix =~ s/\//\\/g;
            return "$MOUNTS{$_}\\$suffix";
        }
    }
    $fp =~ s/\//\\/g;
    return $ROOTMOUNT.$fp;
}

sub cygwin2winpath
{
    my $fp = $_[0];
    if (substr($fp,1,1) eq ':')
    {
        $fp =~ s/\//\\/g;
        return $fp;
    }
    if (substr($fp,0,1) ne '/')
    {
        $fp =~ s/\//\\/g;
        return "$WD\\$fp";
    }
    return check_mounts($fp);
}

sub linux2winpath
{
    my $fp = $_[0];
    if (substr($fp,0,1) ne '/') {
        $fp = cwd() . $fp;
    }
    return check_mounts($fp);
}

sub convert_line
{
    if (/^([^ :]+):([0-9]+):([0-9]+): (.*)$/) {
        $_ = &$unix2winpath($1)."($2,$3) : $4\n";
    } elsif (/^(In file included from |\s+from )([^ :]+):([0-9]+)(:([0-9]+))?[,:]$/) {
        my $a = $5 || 0;
        $_ = &$unix2winpath($2)."($3,$a) : <==== Included from here (double-click to go to line)\n";
    }
}

sub setup
{
    if (-d $ENV{WINDIR}) {
        $WD = `cmd /c cd`;
        $/ = "\r\n"; chomp $WD; $/ = "\n";
        $unix2winpath=\&cygwin2winpath;
    
        foreach(`mount`)
        {
            if (/^([^ \t]+) on ([^ \t]+) /)
            {
                if ($2 eq '/')
                {
                    $ROOTMOUNT = $1;
                }
                else
                {
                    $MOUNTS{$2} = $1;
                }
            }
        }
    } else {
        use Cwd;
        my $suff;
        for my $from (grep { /^MAP_FROM_(.+)$/ and $suff=$1 } keys %ENV) {
            my $to = "MAP_TO_${suff}";
            my ($from_, $to_);
            if (exists $ENV{$to} and $from_=$ENV{$from} and $to_=$ENV{$to}) {
               if (substr($from_, 0, 1) ne '/') {
                    $from_ = $ENV{HOME}. "/${from_}";
                }
                $MOUNTS{$from_} = $to_;
            }
        }
        $ROOTMOUNT = "";
        $unix2winpath=\&linux2winpath;
    }
}

use File::Basename;
use IPC::Open3;
use POSIX ":sys_wait_h";
use IO::Select;

my $invoked_name = $0;
$invoked_name =~ s|\\|/|g;
$invoked_name = basename($invoked_name);
$invoked_name = 'g++'
    if $invoked_name eq 'gcc2msvc.pl';

my $exec = "/usr/bin/${invoked_name}";
my $exit_status = -1;

if (!defined $ENV{VisualStudioVersion}) {
    exec $exec, @ARGV or
        die "Couldn't exec $exec: $!\n";
}

setup();
my $pid = open3(\*CHLD_IN, \*CHLD_OUT, \*CHLD_ERR, $exec, @ARGV);
die "Execute ${exec} failed!"
    unless $pid > 0;
close CHLD_IN;
my $s = IO::Select->new(\*CHLD_OUT, \*CHLD_ERR);

while (my @ready = $s->can_read) {
    foreach my $fh (@ready) {
        my $out = (
            $fh == \*CHLD_OUT ?
                \*STDOUT :
                \*STDERR);

        while (<$fh>) {
            convert_line;
            print $out $_;
        }
    }
    my $res = waitpid($pid, WNOHANG);
    if ($res == $pid || $res == -1) {
        $exit_status = ($? >> 8);
        last;
    }
}

close CHLD_OUT;
close CHLD_ERR;

exit $exit_status;
