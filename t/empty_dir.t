use strict;
use Filesys::Notify::Simple;
use Test::More;
use Test::SharedFork;
use File::Temp qw( tempdir );

use FindBin;

plan tests => 6;

my $dir = tempdir( DIR => "$FindBin::Bin/x" );
my $w = Filesys::Notify::Simple->new([ "$dir" ]);

mkdir "$dir/root";


my $pid = fork;
if ($pid == 0) {
    Test::SharedFork->child;
    sleep 3;
    note "mkdir subroot\n";
    mkdir "$dir/subroot";
    sleep 3;
    note "mkdir subroot/deep\n";
    mkdir "$dir/subroot/deep";
    sleep 3;
    note "mkdir subroot/deep/down\n";
    mkdir "$dir/subroot/deep/down";
    sleep 3;
    note "rmdir subroot/deep/down\n";
    rmdir "$dir/subroot/deep/down";
    sleep 3;
    note "rmdir subroot/deep\n";
    rmdir "$dir/subroot/deep";
    sleep 3;
    note "rmdir subroot\n";
    rmdir "$dir/subroot";
} elsif ($pid != 0) {
    Test::SharedFork->parent;
    my $event;
    alarm 10;
    note "wait mkdir subroot\n";
    $w->wait(sub { $event = shift });
    like $event->{path}, qr/subroot/;
    alarm 10;
    note "wait mkdir subroot/deep\n";
    $w->wait(sub { $event = shift });
    like $event->{path}, qr/subroot[\/\\]deep/;
    alarm 10;
    note "wait mkdir subroot/deep/down\n";
    $w->wait(sub { $event = shift });
    like $event->{path}, qr/subroot[\/\\]deep[\/\\]down/;
    alarm 10;
    note "wait rmdir subroot/deep/down\n";
    $w->wait(sub { $event = shift });
    like $event->{path}, qr/subroot[\/\\]deep[\/\\]down/;
    alarm 10;
    note "wait rmdir subroot/deep\n";
    $w->wait(sub { $event = shift });
    like $event->{path}, qr/subroot[\/\\]deep/;
    alarm 10;
    note "wait rmdir subroot\n";
    $w->wait(sub { $event = shift });
    like $event->{path}, qr/subroot/;
    waitpid $pid, 0;
} else {
    die $!;
}


