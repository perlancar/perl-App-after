package App::after;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
#use Log::Any::IfLOG qw($log);

our %SPEC;
#require Exporter;
#our @ISA       = qw(Exporter);
#our @EXPORT_OK = qw(after);

our $DEBUG = $ENV{DEBUG};

$SPEC{after} = {
    v => 1.1,
    summary => 'Run command after delay and/or some other event',
    description => <<'_',

`after` will run command after all the specified conditions are met. A condition
can be: delay (`--delay`), current time (`--time`), system uptime (`--uptime`),
system load falling below a certain value (`--load-below`), system load rising
above a certain value (`--load-above`). More conditions will be available in the
future.

_
    args => {
        command => {
            schema => ['array*', of=>'str*', min_len=>1],
            req => 1,
            pos => 0,
            greedy => 1,
        },

        delay => {
            schema => 'duration*',
            'x.perl.coerce_to' => 'int(secs)',
            tags => ['category:condition'],
            cmdline_aliases => {d=>{}},
        },
        time => {
            schema => 'date*',
            'x.perl.coerce_to' => 'int(epoch)',
            tags => ['category:condition'],
        },
        uptime => {
            schema => 'duration*',
            'x.perl.coerce_to' => 'int(secs)',
            tags => ['category:condition'],
        },
        load_below => {
            schema => ['float*', min=>0],
            tags => ['category:condition'],
        },
        load_above => {
            schema => ['float*', min=>0],
            tags => ['category:condition'],
        },
        # XXX: condition: we are online
        # XXX: condition: we are offline
        # XXX: condition: a program is running
        # XXX: condition: a program is not running
        # XXX: condition: screensaver is running
        # XXX: condition: screensaver is not running

        or => {
            summary =>
                'Run command after one condition (instead of all) is met',
            schema => 'bool',
            tags => ['category:logic'],
        },
        none => {
            summary =>
                'Run command when none of the conditions are met',
            schema => 'bool',
            tags => ['category:logic'],
        },
    },
    args_rels => {
        choose_one => ['or', 'none'],
    },
    links => [
        {
            url => 'http://onegeek.org/~tom/software/delay/',
        },
    ],
    examples => [
        {
            argv => ['--delay', '30m', 'cmd'],
            summary => 'Run command after 30-minute delay',
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            argv => ['--delay', '12h', '--time', '2016-04-18', 'cmd'],
            summary => 'Run command after 12 hour delay and time has passed 2016-04-18',
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            argv => ['--or', '--delay', '12h', '--time', '2016-04-18', 'cmd'],
            summary => 'Run command after 12 hour delay *or* time has passed 2016-04-18',
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            argv => ['--uptime', '2d', 'cmd'],
            summary => 'Run command after system uptime is 2 days',
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            argv => ['--load-above', '2.5', 'cmd'],
            summary => 'Run command after system load is above 2.5',
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            argv => ['--load-above', '1', '--load-below', 5, 'cmd'],
            summary => 'Run command after system load is between 1 and 5',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
    #result_naked => 1,
};
sub after {
    my %args = @_;
    my $cmd = $args{command};

    my $start_time = time();

    my @conds;

    if (defined $args{delay}) {
        push @conds, {
            freq => 1,
            check => sub {
                my $now = time();
                say "D:Checking delay: current=", ($now-$start_time) if $DEBUG;
                $now >= $start_time + $args{delay};
            },
        };
    }
    if (defined $args{time}) {
        push @conds, {
            freq => 1,
            check => sub {
                my $now = time();
                say "D:Checking time: current=$now, target=$args{time}" if $DEBUG;
                $now >= $args{time};
            },
        };
    }
    if (defined $args{uptime}) {
        require Unix::Uptime;
        push @conds, {
            freq => 1,
            check => sub {
                my $uptime = Unix::Uptime->uptime;
                say "D:Checking uptime: current=$uptime, target=$args{uptime}" if $DEBUG;
                $uptime >= $args{uptime};
            },
        };
    }
    if (defined($args{load_below}) || defined($args{load_above})) {
        require Unix::Uptime;
        push @conds, {
            freq => 5,
            check => sub {
                my @load = Unix::Uptime->load();
                say "D:Checking load_below/load_above: current=$load[0]" if $DEBUG;
                return 0 if defined($args{load_below}) &&
                    $load[0] >= $args{load_below};
                return 0 if defined($args{load_above}) &&
                    $load[0] <= $args{load_above};
                1;
            },
        };
    }

    goto RUN_PROGRAM unless @conds;

    $_->{counter} = 0 for @conds;

    while (1) {
        my $num_checked = 0;
        my $num_met = 0;
        for my $cond (@conds) {
            $cond->{counter}--;
            next unless $cond->{counter} <= 0;
            $num_checked++;
            $cond->{counter} = $cond->{freq};
            next unless $cond->{check}->();
            $num_met++;
            last if $args{or} || $args{none};
        }

        if ($num_checked) {
            if ($args{or}) {
                last if $num_met;
            } elsif ($args{none}) {
                last if $num_checked == @conds && !$num_met;
            } else {
                last if $num_met == @conds;
            }
        }

        sleep 1;
    }

  RUN_PROGRAM:
    system {$cmd->[0]} @$cmd;
    my $num = $?;

    if ($num == -1) {
        return [500, "Program failed to run: $!"];
    } elsif ($num) {
        my $exit_code = $num >> 8;
        return [
            500,
            "Program exit non-success (exit code $exit_code)",
            undef,
            {"cmdline.exit_code" => $exit_code},
        ];
    } else {
        return [200, "OK"];
    }
}

1;
#ABSTRACT:

=head1 DESCRIPTION

See the included script L<after>.


=head1 ENVIRONMENT

=head2 DEBUG
