# ABSTRACT: Specification for commandline app
use strict;
use warnings;
package App::Spec;
use 5.010;

our $VERSION = '0.000'; # VERSION

use App::Spec::Command;
use App::Spec::Option;
use App::Spec::Parameter;
use App::Spec::Completion::Zsh;
use App::Spec::Completion::Bash;
use List::Util qw/ any /;
use YAML::Syck ();

use Moo;

has name => ( is => 'rw' );
has title => ( is => 'rw' );
has options => ( is => 'rw' );
has commands => ( is => 'rw' );

my $DATA = do { local $/; <DATA> };
my $default_spec;

sub _read_default_spec {
    $default_spec ||= YAML::Syck::Load($DATA);
    return $default_spec;
}

sub read {
    my ($class, $file) = @_;
    unless (defined $file) {
        die "No filename given";
    }

    my $spec;
    if (ref $file eq 'GLOB') {
        my $data = do { local $/; <$file> };
        $spec = eval { YAML::Syck::Load($data) };
    }
    elsif (not ref $file) {
        $spec = eval { YAML::Syck::LoadFile($file) };
    }
    elsif (ref $file eq 'HASH') {
        $spec = $file;
    }

    unless ($spec) {
        die "Error reading '$file': $@";
    }

    my $default;
    {
        $default = $class->_read_default_spec;

        for my $opt (@{ $default->{options} }) {
            my $name = $opt->{name};
            unless (any { $_->{name} eq $name } @{ $spec->{options} }) {
                push @{ $spec->{options} }, $opt;
            }
        }

        for my $key (keys %{ $default->{commands} } ) {
            my $cmd = $default->{commands}->{ $key };
            $spec->{commands}->{ $key } ||= $cmd;
        }
    }

    # add subcommands to help command
    my $help_subcmds = $spec->{commands}->{help}->{subcommands} ||= {};
    $class->_add_subcommands($help_subcmds, $spec->{commands});

    my $commands;
    for my $name (keys %{ $spec->{commands} || [] }) {
        my $cmd = $spec->{commands}->{ $name };
        $commands->{ $name } = App::Spec::Command->build({
            name => $name,
            %$cmd,
        });
    }

    my $self = $class->new({
        name => $spec->{name},
        title => $spec->{title},
        options => [map {
            App::Spec::Option->build($_)
        } @{ $spec->{options} || [] }],
        commands => $commands,
    });
    return $self;
}

sub _add_subcommands {
    my ($self, $commands1, $commands2) = @_;
    for my $name (keys %{ $commands2 || {} }) {
        next if $name eq "help";
        my $cmd = $commands2->{ $name };
        $commands1->{ $name } = {
            name => $name,
            subcommands => {},
        };
        my $subcmds = $cmd->{subcommands} || {};
        $self->_add_subcommands($commands1->{ $name }->{subcommands}, $subcmds);
    }
}

sub usage {
    my ($self, $cmds) = @_;
    my $appname = $self->name;

    my ($options, $parameters, $subcmds) = $self->gather_options_parameters($cmds);
    my $usage = "Usage: $appname @$cmds";

    my $body = '';
    if (keys %$subcmds) {
        my $maxlength = 0;
        my @table;
        $usage .= " <subcommands>";
        $body .= "Subcommands:\n";
        for my $name (sort keys %$subcmds) {
            my $cmd_spec = $subcmds->{ $name };
            my $summary = $cmd_spec->summary;
            push @table, [$name, $summary];
            if (length $name > $maxlength) {
                $maxlength = length $name;
            }
        }
        $body .= $self->_output_table(\@table, [$maxlength]);
    }

    if (@$parameters) {
        my $maxlength = 0;
        my @table;
        for my $param (@$parameters) {
            my $name = $param->{name};
            my $summary = $param->summary;
            $usage .= " <$name>";
            push @table, [$name, $summary];
            if (length $name > $maxlength) {
                $maxlength = length $name;
            }
        }
        $body .= "Parameters:\n";
        $body .= $self->_output_table(\@table, [$maxlength]);
    }

    if (@$options) {
        $usage .= " [options]";
        my $maxlength = 0;
        my @table;
        for my $opt (sort { $a->name cmp $b->name } @$options) {
            my $name = $opt->name;
            my $aliases = $opt->aliases;
            my $summary = $opt->summary;
            my @names = map {
                length $_ > 1 ? "--$_" : "-$_"
            } ($name, @$aliases);
            my $string = "@names";
            if (length $string > $maxlength) {
                $maxlength = length $string;
            }
            push @table, [$string, $summary];
        }
        $body .= "\nOptions:\n";
        $body .= $self->_output_table(\@table, [$maxlength]);
    }

    return "$usage\n\n$body";
}

sub _output_table {
    my ($self, $table, $lengths) = @_;
    my $string = '';
    my @lengths = map {
        defined $lengths->[$_] ? "%-$lengths->[$_]s" : "%s"
    } 0 .. @{ $table->[0] } - 1;
    for my $row (@$table) {
        $string .= sprintf join('  ', @lengths) . "\n", @$row;
    }
    return $string;
}


sub gather_options_parameters {
    my ($self, $cmds) = @_;
    my @options;
    my @parameters;
    my $global_options = $self->options;
    my $commands = $self->commands;
    push @options, @$global_options;

    for my $cmd (@$cmds) {
        my $cmd_spec = $commands->{ $cmd };
        my $options = $cmd_spec->options || [];
        my $parameters = $cmd_spec->parameters || [];
        push @options, @$options;
        push @parameters, @$parameters;

        $commands = $cmd_spec->subcommands || {};

    }
    return \@options, \@parameters, $commands;
}

sub generate_completion {
    my ($self, %args) = @_;
    my $shell = delete $args{shell};

    if ($shell eq "zsh") {
        my $completer = App::Spec::Completion::Zsh->new({
            spec => $self,
        });
        return $completer->generate_completion(%args);
    }
    elsif ($shell eq "bash") {
        my $completer = App::Spec::Completion::Bash->new({
            spec => $self,
        });
        return $completer->generate_completion(%args);
    }
}


sub make_getopt {
    my ($self, $options, $result, $specs) = @_;
    my @getopt;
    for my $opt (@$options) {
        my $name = $opt->name;
        my $spec = $name;
        unless ($opt->type eq 'bool') {
            $spec .= "=s";
        }
        $specs->{ $name } = $opt;
        push @getopt, $spec, \$result->{ $name },
    }
    return @getopt;
}

1;

__DATA__
options:
    -   name: help
        description: Show command help
        type: bool
        aliases:
        - h
commands:
    help:
        op: cmd_help
        summary: Show command help
        options:
        -   name: all
            type: bool
    _complete:
        summary: Generate self completion
        options:
            -   name: name
                description: name of the program
        subcommands:
            zsh:
                op: cmd_self_completion_zsh
                summary: for zsh
            bash:
                op: cmd_self_completion_bash
                summary: for bash
                options:
                    -   name: without-description
                        type: bool
                        default: false
                        description: generate without description