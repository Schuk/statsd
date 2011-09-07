package Statsd;

# ABSTRACT: Sends statistics to the stats daemon over UDP
# Cosimo Streppone <cosimo@cpan.org>

use strict;
use warnings;
use IO::Socket ();

our $HOST = 'localhost';
our $PORT = 8125;

=head1 NAME

Statsd - Perl client for Etsy's statsd daemon

=head1 SYNOPSIS

    # Configure where to send events
    # That's where your statsd daemon is listening.
    $Statsd::HOST = 'localhost';    # Default
    $Statsd::PORT = 8125;           # Default

    # Create Statsd object.
    my $statsd = Statsd->new(
        host => 'localhost',         # Optional
        port => '8125'               # Optional
    );

    # Keep track of events as counters
    $statsd->increment('site.logins');
    $statsd->increment('database.connects');

    # Log timing of events, ex. db queries
    use Time::HiRes;
    my $start_time = [ Time::HiRes::gettimeofday ];
    # do the complex database query
    $statsd->timing(
        'database.complexquery',
        Time::HiRes::tv_interval($start_time)
    );

=head1 DESCRIPTION

This module implement a UDP client for the B<statsd> statistics
collector daemon in use at Etsy.com.

You want to use this module to track statistics in your Perl
application, such as how many times a certain event occurs
(user logins in a web application, or database queries issued),
or you want to time and then graph how long certain events take,
like database queries execution time or time to download a
certain file, etc...

If you're uncertain whether you'd want to use this module or
statsd, then you can read some background information here:

    http://codeascraft.etsy.com/2011/02/15/measure-anything-measure-everything/

The github repository for statsd is:

    http://github.com/etsy/statsd

By default the client will try to send statistic metrics to
C<localhost:8125>, but you can change the default hostname and port
with:

    $Statsd::HOST = 'your.statsd.hostname.net';
    $Statsd::PORT = 9999;

just after including the C<Statsd> module.
Or you can specify the host and port while creating the Statsd object:

    my $stats->new(
        host => 'your.statsd.hostname.net',
        port => 9999;
    );

=head1 FUNCTIONS

=cut

=head2 new

create a new Statsd Object. The UDP Socket is created here
    
    my $stats->new(
        host => 'your.statsd.hostname.net',
        port => 9999;
    );


=cut

sub new {
    my $class = shift();
    my %params = @_;
    my $self = {};

    $HOST = $params{host} if $params{host};
    $PORT = $params{port} if $params{port};
    $self->{host} = $HOST;
    $self->{port} = $PORT;
    
    $self->{udp_sock} = IO::Socket::INET->new( Proto    => 'udp',
        PeerAddr => $HOST,
        PeerPort => $PORT,
    ) or return;

    bless $self, $class;


    return $self;
}

=head2 C<timing($stat, $time, $sample_rate = 1)>

Log timing information.
Time is assumed to be in milliseconds (ms).

    $statsd->timing('some.time', 500);

=cut

sub timing {
    my ($self, $stat, $time, $sample_rate) = @_;

    my $stats = {
        $stat => sprintf "%d|ms", $time
    };

    return $self->send($stats, $sample_rate);
}

=head2 C<increment($stats, $sample_rate=1)>

Increments one or more stats counters

    # +1 on 'some.int'
    $statsd->increment('some.int');

    # 0.5 = 50% sampling
    $statsd->increment('some.int', 0.5);

To increment more than one counter at a time,
you can B<pass an array reference>:

    $statsd->increment(['grue.dinners', 'room.lamps'], 1);

=cut

sub increment {
    my ($self, $stats, $sample_rate) = @_;

    return $self->update_stats($stats, 1, $sample_rate);
}

=head2 C<decrement($stats, $sample_rate=1)>

Same as increment, but decrements. Yay.

    $statsd->decrement('some.int')

=cut

sub decrement {
    my ($self, $stats, $sample_rate) = @_;

    return $self->update_stats($stats, -1, $sample_rate);
}

=head2 C<update_stats($stats, $delta=1, $sample_rate=1)>

Updates one or more stats counters by arbitrary amounts

    $statsd->update_stats('some.int', 10)

equivalent to:

    $statsd->update_stats('some.int', 10, 1)

A sampling rate less than 1 means only update the stats
every x number of times (0.1 = 10% of the times).

=cut

sub update_stats {
    my ($self, $stats, $delta, $sample_rate) = @_;

    $delta = 1 unless defined $delta;
    $sample_rate = 1 unless defined $sample_rate;

    if (! ref $stats) {
        $stats = [ $stats ];
    }
    elsif (ref $stats eq 'HASH') {
        Carp::croak("Usage: update_stats(\$str, ...) or update_stats(\\\@list, ...)");
    }

    my %data = map { $_ => sprintf "%s|c", $delta } @{ $stats };

    return $self->send(\%data, $sample_rate)
}

=head2 C<send(\%data, $sample_rate=1)>

Squirt the metrics over UDP.

    $statsd->send({ 'some.int' => 1 });

=cut

sub send {
    my ($self, $data, $sample_rate) = @_;

    my %sampled_data;

    if ($sample_rate < 1) {
        if (rand() <= $sample_rate) {
            while (my ($stat, $value) = each %{ $data }) {
                $sampled_data{$stat} = sprintf "%s|@%s", $value, $sample_rate;
            }
        }
    }
    else {
        %sampled_data = %{ $data };
    }
    # We don't want to die if $statsd->send() doesn't work...
    # We could though:
    #
    # or die "Could not create UDP socket: $!\n";

    my $all_sent = 1;

    for my $stat (keys %sampled_data) {
        my $value =$data->{$stat};
        my $packet = "$stat:$value";
        $self->{udp_sock}->send($packet);
        # XXX If you want warnings...
        # or do {
        #    warn "[" . localtime() . "] UDP packet '$packet' send failed\n";
        #    $all_sent = 0;
        #};
    }

    return $all_sent;
}

1;
