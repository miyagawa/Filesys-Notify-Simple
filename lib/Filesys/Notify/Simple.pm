package Filesys::Notify::Simple;

use strict;
use 5.008_001;
our $VERSION = '0.01';

use Carp ();

sub new {
    my($class, $path) = @_;

    unless (ref $path eq 'ARRAY') {
        Carp::croak('Usage: Filesys::Notify::Simple->new([ $path1, $path2 ])');
    }

    my $self = bless { paths => $path }, $class;
    $self->init;

    $self;
}

sub wait {
    my($self, $cb) = @_;

    $self->{watcher} ||= $self->{watcher_cb}->(@{$self->{paths}});
    $self->{watcher}->($cb);
}

sub init {
    my $self = shift;

    local $@;
    if ($^O eq 'linux' && eval { require Linux::Inotify2; 1 }) {
        $self->{watcher_cb} = \&wait_inotify2;
    } elsif ($^O eq 'darwin' && eval { require Mac::FSEvents; 1 }) {
        $self->{watcher_cb} = \&wait_fsevents;
    } else {
        $self->{watcher_cb} = \&wait_timer;
    }
}

sub wait_inotify2 {
    my @path = @_;

    Linux::Inotify2->import;
    my $inotify = Linux::Inotify2->new;

    for my $path (@path) {
        $inotify->watch($path, &IN_MODIFY|&IN_CREATE|&IN_DELETE|&IN_DELETE_SELF|&IN_MOVE_SELF);
    }

    return sub {
        my $cb = shift;
        $inotify->blocking(1);
        my @events = $inotify->read;
        $cb->(map { +{ dir => $_->name, path => $_->fullname } } @events);
    };
}

sub wait_fsevents {
    require IO::Select;
    my @path = @_;

    my $sel = IO::Select->new;

    my %events;
    for my $path (@path) {
        my $fs = Mac::FSEvents->new({ path => $path, latency => 0.2 });
        my $fh = $fs->watch;
        $sel->add($fh);
        $events{fileno $fh} = $fs;
    }

    return sub {
        my $cb = shift;

        my @ready = $sel->can_read;
        my @events;
        for my $fh (@ready) {
            my $fs = $events{fileno $fh};
            for my $event ($fs->read_events) {
                push @events, { dir => $event->path, path => undef };
            }
        }

        $cb->(@events);
    };
}

sub wait_timer {
    my @path = @_;

    my $fs = _full_scan(@path);

    return sub {
        my $cb = shift;
        my @events;
        while (1) {
            my $new_fs = _full_scan(@path);
            _compare_fs($fs, $new_fs, sub { push @events, { dir => $_[1], path => $_[0] } });
            $fs = $new_fs;
            last if @events;
            sleep 2;
        };
        $cb->(@events);
    };
}

sub _compare_fs {
    my($old, $new, $cb) = @_;

    for my $path (keys %$old) {
        if (!exists $new->{$path}) {
            $cb->($path, $old->{$path}{dir}); # deleted
        } elsif (!$new->{$path}{is_dir} &&
                 ( $old->{$path}{mtime} != $new->{$path}{mtime} || $old->{$path}{size} != $new->{$path}{size})) {
            $cb->($path, $old->{$path}{dir}); # size/mtime updated
        }
    }

    for my $path (sort grep { !exists $old->{$_} } keys %$new) {
        $cb->($path, $new->{$path}{dir}); # created
    }
}

sub _full_scan {
    my @path = @_;
    require File::Find;

    my %map;
    for my $path (@path) {
        File::Find::finddepth({
            wanted => sub { $map{$File::Find::fullname} = _stat($File::Find::fullname, $path) },
            follow_fast => 1,
            no_chdir => 1,
        }, @path);
    }

    return \%map;
}

sub _stat {
    my($path, $dir) = @_;
    my @stat = stat $path;
    return { path => $path, mtime => $stat[9], size => $stat[7], is_dir => -d _, dir => $dir };
}


1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Filesys::Notify::Simple - Simple and dumb file system watcher

=head1 SYNOPSIS

  use Filesys::Notify::Simple;

  my $watcher = Filesys::Notify::Simple->new([ "." ]);
  $watcher->wait(sub {
      for my $event (@_) {
          $event->{dir}; # directory you were watching
          $event->{path} # full path of the file updated. Maybe undef in some environments
      }
  });

=head1 DESCRIPTION

Filesys::Notify::Simple is a simple but unified interface to get
notifications of changes to a given filesystem path. It utilizes
inotify2 on Linux and fsevents on OS X if they're installed, with a
fallback to the full directory scan if they're not available.

There are some limitations in this module. If you don't like it, use
L<File::ChangeNotify>.

=over 4

=item *

There is no file name based filter. Do it in your own code.

=item *

The full path is not always available, which is due to the limitation
of Apple's fsevents API.

=item *

You can not get types of events (created, updated, deleted).

=item *

Curently C<wait> method blocks.

=back

In return, this module doesn't depend on any non-core
modules. Platform specific optimizations with L<Linux::Inotify2> and
L<Mac::FSEvents> are truely optional.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<File::ChangeNotify> L<Mac::FSEvents> L<Linux::Inotify2>

=cut
