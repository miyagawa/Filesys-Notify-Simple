use strict;
use Filesys::Notify::Simple;
use Test::More;
use Test::SharedFork;
use FindBin;
use File::Temp qw( tempdir );

my $dir = tempdir( DIR => "$FindBin::Bin/x" );


plan tests => 2;

my $w = Filesys::Notify::Simple->new([ "lib", "$dir" ]);

my $pid = fork;
if ($pid == 0) {
    Test::SharedFork->child;
    sleep 3;
    my $test_file = "$dir/rm_create.data";
    open my $out, ">", $test_file;
    print $out "foo" . time;
    close $out;
    sleep 3;
    unlink $test_file;
} elsif ($pid != 0) {
    Test::SharedFork->parent;
    my $event;
    for (1..2) {
        alarm 10;
        $w->wait(sub { $event = shift }); # create
        like $event->{path}, qr/rm_create\.data/;
    }

    waitpid $pid, 0;
} else {
    die $!;
}


