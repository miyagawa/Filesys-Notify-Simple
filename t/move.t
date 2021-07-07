use strict;
use Config;
use Filesys::Notify::Simple;
use Test::More;
use Test::SharedFork;
use File::Temp qw( tempdir );

use FindBin;

plan skip_all => "fork not supported on this platform"
  unless $Config::Config{d_fork} || $Config::Config{d_pseudofork} ||
    (($^O eq 'MSWin32' || $^O eq 'NetWare') and
     $Config::Config{useithreads} and
     $Config::Config{ccflags} =~ /-DPERL_IMPLICIT_SYS/);

plan tests => 2;

my $dir = tempdir( DIR => "$FindBin::Bin/x" );
my $w = Filesys::Notify::Simple->new([ "lib", "$dir" ]);

my $test_file = "$dir/move_create.data";
my $test_file_to = "$dir/move_create.data.to";


my $pid = fork;
if ($pid == 0) {
    Test::SharedFork->child;
    sleep 3;
    open my $out, ">", $test_file;
    print $out "foo" . time;
    close $out;
    sleep 3;
    rename($test_file => $test_file_to);
} elsif ($pid != 0) {
    Test::SharedFork->parent;
    my $event;
    for (1..2) {
        alarm 10;
        $w->wait(sub { $event = shift }); # create
        like $event->{path}, qr/move_create\.data/;
    }
    unlink $test_file_to;

    waitpid $pid, 0;
} else {
    die $!;
}


