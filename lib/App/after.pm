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

$SPEC{after} = {
    v => 1.1,
    summary => 'Run command after delay and/or some other event',
    description => <<'_',

`after` will run command after all the specified conditions are met. A condition
can be: delay (`--delay`), time (`--time`), system load falling below a certain
value (`--load-below`), system load rising above a certain value
(`--load-above`). More conditions will be available in the future.

_
    args => {
        command => {
            schema => ['array*', of=>'str*', min_len=>1],
            req => 1,
            pos => 0,
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
        load_below => {
            schema => ['int*', min=>0],
        },
        load_above => {
            schema => ['int*', min=>0],
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
        },
        none => {
            summary =>
                'Run command when none of the conditions are met',
            schema => 'bool',
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
    ],
    #result_naked => 1,
}
sub after {
    my %args = @_;
    my $cmd = $args{command};

    my $start_time = time();

    my @conds;

    if (defined $args{delay}) {
        push @conds, {
            freq => 1,
            check => sub { time() >= $start_time() + $args{delay} },
        };
    }
    if (defined $args{time}) {
        push @conds, {
            freq => 1,
            check => sub { time() >= $args{time} },
        };
    }
    if (defined($args{load_below}) || defined($args{load_above})) {
        require Unix::Uptime;
        push @conds, {
            freq => 5,
            check => sub {
                my @load = Unix::Uptime->load();
                return 0 if defined($args{load_below}) &&
                    $load[0] >= $args{load_below};
                return 0 if defined($args{load_above}) &&
                    $load[0] <= $args{load_above};
                1;
            },
        };
    }

    while (1) {
        my $num_checked = 0;
        my $num_met = 0;
        for my $cond (@conds) {
            $cond->{counter}++;
            last unless $cond->{counter} >= $cond->{freq};
            $num_checked++;
            $cond->{counter} = 0;
            last unless $cond->{check}->();
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

    system {$cmd->[0]} @$cmd;
    my $exit_code = $?;

    return [
        $exit_code ? 500 : 200,
        $exit_code ? "Program failed" : "OK",
        undef,
        {"cmdline.exit_code" => $exit_code},
    ];
}

1;
#ABSTRACT:

=head1 DESCRIPTION

See the included script L<after>.
