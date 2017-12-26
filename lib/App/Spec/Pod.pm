# ASTRACT: Generates Pod from App::Spec objects
use strict;
use warnings;
package App::Spec::Pod;

our $VERSION = '0.000'; # VERSION

use Text::Table;

use Moo;
use App::Spec::Types qw/AppSpec/;

has spec => ( is => 'ro', required => 1, isa => AppSpec );

sub generate {
    my ($self) = @_;
    my $spec = $self->spec;
    my $appname = $spec->name;
    my $title = $spec->title;
    my $abstract = $spec->abstract // '';
    my $description = $spec->description // '';
    my $subcmds = $spec->subcommands;
    my $global_options = $spec->options;

    $self->markup(text => \$abstract);
    $self->markup(text => \$description);

    my @subcmd_pod = $self->subcommand_pod(
        commands => $subcmds,
    );
    my $option_string = '';
    if (@$global_options) {
        $option_string = "=head2 GLOBAL OPTIONS\n\n" . $self->options2pod(
            options => $global_options,
        );
    }

    my $pod = <<"EOM";
\=head1 NAME

$appname - $title

\=head1 ABSTRACT

$abstract

\=head1 DESCRIPTION

$description

$option_string

\=head2 SUBCOMMANDS

@{[ join '', @subcmd_pod ]}
EOM

}

sub subcommand_pod {
    my ($self, %args) = @_;
    my $spec = $self->spec;
    my $appname = $spec->name;
    my $commands = $args{commands};
    my $previous = $args{previous} || [];

    my @pod;
    my %keys;
    @keys{ keys %$commands } = ();
    my @keys;
    if (@$previous) {
        @keys = sort keys %keys;
    }
    else {
        for my $key (qw/ help _meta /) {
            if (exists $keys{ $key }) {
                push @keys, $key;
                delete $keys{ $key };
            }
        }
        unshift @keys, sort keys %keys;
    }
    for my $name (@keys) {
        my $cmd_spec = $commands->{ $name };
        my $name = $cmd_spec->name;
        my $summary = $cmd_spec->summary;
        my $description = $cmd_spec->description;
        my $subcmds = $cmd_spec->subcommands;
        my $parameters = $cmd_spec->parameters;
        my $options = $cmd_spec->options;

        $self->markup(text => \$summary);
        $self->markup(text => \$description);

        my $desc = '';
        if (length $summary) {
            $desc .= "$summary\n\n";
        }
        if (length $description) {
            $desc .= "$description\n\n";
        }

        my $usage = "$appname @$previous $name";
        if (keys %$subcmds) {
            $usage .= " <subcommands>";
        }

        my $option_string = '';
        if (@$options) {
            $usage .= " [options]";
            $option_string = "Options:\n\n" . $self->options2pod(
                options => $options,
            );
        }

        if (length $option_string) {
            $desc .= "$option_string\n";
        }

        my $param_string = '';
        if (@$parameters) {
            $param_string = "Parameters:\n\n" . $self->params2pod(
                parameters => $parameters,
            );
            for my $param (@$parameters) {
                my $name = $param->name;
                my $required = $param->required;
                $usage .= " " . $param->to_usage_header;
            }
        }
        if (length $param_string) {
            $desc .= $param_string;
        }

        my $pod = <<"EOM";
\=head3 @$previous $name

    $usage

$desc
EOM
        if (keys %$subcmds and $name ne "help") {
            my @sub = $self->subcommand_pod(
                previous => [@$previous, $name],
                commands => $subcmds,
            );
            $pod .= join '', @sub;
        }
        push @pod, $pod;
    }
    return @pod;
}

sub params2pod {
    my ($self, %args) = @_;
    my $params = $args{parameters};
    my @rows;
    my $tb = Text::Table->new;
    for my $param (@$params) {
        my $required = $param->required ? '*' : '';
        my $summary = $param->summary;
        my $multi = '';
        if ($param->mapping) {
            $multi = '{}';
        }
        elsif ($param->multiple) {
            $multi = '[]';
        }
        my $flags = $self->spec->_param_flags_string($param);
        push @rows, ["    " . $param->name, " " . $required, $multi, $summary . $flags];
    }
    $tb->load(@rows);
    return "$tb";
}

sub options2pod {
    my ($self, %args) = @_;
    my $options = $args{options};
    my @rows;
    my $tb = Text::Table->new;
    for my $opt (@$options) {
        my $name = $opt->name;
        my $aliases = $opt->aliases;
        my $summary = $opt->summary;
        my $required = $opt->required ? '*' : '';
        my $multi = '';
        if ($opt->mapping) {
            $multi = '{}';
        }
        elsif ($opt->multiple) {
            $multi = '[]';
        }
        my @names = map {
            length $_ > 1 ? "--$_" : "-$_"
        } ($name, @$aliases);
        my $flags = $self->spec->_param_flags_string($opt);
        push @rows, ["    @names", " " . $required, $multi, $summary . $flags];
    }
    $tb->load(@rows);
    return "$tb";
}

sub markup {
    my ($self, %args) = @_;
    my $text = $args{text};
    return unless defined $$text;
    my $markup = $self->spec->markup // '';
    if ($markup eq "swim") {
        $$text = $self->swim2pod($$text);
    }
}
sub swim2pod {
    my ($self, $text) = @_;
    require Swim;
    my $swim = Swim->new(text => $text);
    my $pod = $swim->to_pod;
}

1;

__END__

=pod

=head1 NAME

App::Spec::Pod - Generates Pod from App::Spec objects

=item SYNOPSIS

    my $generator = App::Spec::Pod->new(
        spec => $appspec,
    );
    my $pod = $generator->generate;

=head1 METHODS

=over 4

=item generate

    my $pod = $generator->generate;

=item markup

    $pod->markup(text => \$abstract);

Applies markup defined in the spec to the text argument.

=item options2pod

    my $option_string = "Options:\n\n" . $self->options2pod(
        options => $options,
    );

=item params2pod

    my $param_string = "Parameters:\n\n" . $self->params2pod(
        parameters => $parameters,
    );

=item subcommand_pod

Generates pod for subcommands recursively

    my @pod = $self->subcommand_pod(
        previous => [@previous_subcmds],
        commands => $subcmds,
    );

=item swim2pod

    my $pod = $self->swim2pod($swim);

Converts Swim markup to Pod.
See L<Swim>.

=item spec

Accessor for L<App::Spec> object

=back

=cut

