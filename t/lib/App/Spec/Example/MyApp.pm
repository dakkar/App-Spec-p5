package App::Spec::Example::MyApp;
use warnings;
use strict;
use 5.010;

use base 'App::Spec::Run';

sub _dump_hash {
    my ($self, $hash) = @_;
    my @strings;
    for my $key (sort keys %$hash) {
    next unless defined $hash->{ $key };
        push @strings, "$key=$hash->{ $key }";
    }
    return join ",", @strings;
}

sub cook {
    my ($self) = @_;
    my $param = $self->parameters;
    my $opt = $self->options;
    if ($ENV{PERL5_APPSPECRUN_TEST}) {
        say "Subcommands: cook";
        say "Options: " . $self->_dump_hash($opt);
        say "Parameters: " .  $self->_dump_hash($param);
        return;
    }

    my @with;
    my $with = $opt->{with} // '';
    if ($with eq "cow milk") {
        die "Sorry, no cow milk today. go vegan\n";
    }
    push @with, $with if $with;
    push @with, "sugar" if $opt->{sugar};

    say "Starting to cook $param->{drink}"
    . (@with ? " with ". (join " and ", @with) : '');
}

my %countries = (
    Austria => {
      Vienna => { weather => "sunny =)", temperature => 23 },
      Salzburg => { weather => "rainy =(", temperature => 13 },
    },
    Germany => {
      Berlin => { weather => "snow =)", temperature => -2 },
      Hamburg => { weather => "sunny =)", temperature => 19 },
      Frankfurt => { weather => "rainy =(", temperature => 23 },
    },
    Netherlands => {
      Amsterdam => { weather => "rainy =(", temperature => 17 },
      Echt => { weather => "sunny =)", temperature => 37 },
    },
);

sub weather {
    my ($self) = @_;
    my $param = $self->parameters;
    my $cities = $param->{city};
    for my $city (@$cities) {
        my $info = $countries{ $param->{country} }->{ $city };
        my $output = sprintf "Weather in %s/%s: %s", $param->{country}, $city, $info->{weather};
        if ($self->options->{temperature}) {
            my $temp = $info->{temperature};
            my $label = "°C";
            if ($self->options->{fahrenheit}) {
              $temp = int($temp * 9 / 5 + 32);
              $label = "F";
            }
            $output .= " (Temperature: $temp$label)";
        }
        say $output;
    }
}

sub countries {
    say for sort keys %countries;
}

sub cities {
    my ($self) = @_;
    my $country = $self->{options}->{country};
    my @countries = @$country ? @$country : sort keys %countries;
    say for map { sort keys %$_ } @countries{ @countries };
}

sub weather_complete {
    my ($self, $args) = @_;
    my $completion = $args->{completion} or return;
    my $comp_param = $completion->{parameter};

    my $param = $self->parameters;
    if ($comp_param eq "city") {
        my $country = $param->{country};
        my $cities = $countries{ $country } or return;
        return [map { +{ name => $_, description => "$_ ($country)" } } sort keys %$cities];
    }
    elsif ($comp_param eq "country") {
        my @countries = sort keys %countries;
        return \@countries;
    }
    return;
}

sub palindrome{
    my ($self) = @_;
    my $string = $self->parameters->{string};
    say +($string eq reverse $string) ? "yes" : "nope";
}

my %units = (
    temperature => {
        celsius => {
            label => "°C",
        },
        kelvin => {
            label => "K",
        },
        fahrenheit => {
            label => "°F",
        },
    },
);

use constant KELVIN => 273.15;
sub celsius_fahrenheit { $_[0] * 9 / 5 + 32 }
sub fahrenheit_celsius { ($_[0] - 32) / (9 / 5) }
my %conversions = (
    temperature => {
        celsius_fahrenheit => sub {
            return sprintf "%.2f", celsius_fahrenheit($_[0])
        },
        celsius_kelvin => sub {
            return sprintf "%.2f", ($_[0] + KELVIN);
        },
        fahrenheit_celsius => sub {
            return sprintf "%.2f", fahrenheit_celsius($_[0])
        },
        fahrenheit_kelvin => sub {
            return sprintf "%.2f", fahrenheit_celsius($_[0]) + KELVIN
        },
        kelvin_celsius => sub {
            return sprintf "%.2f", $_[0] - KELVIN
        },
        kelvin_fahrenheit => sub {
            return sprintf "%.2f", celsius_fahrenheit($_[0] - KELVIN)
        },
    },
);

sub convert {
    my ($self) = @_;
    my $param = $self->parameters;
    my $source = $param->{source};
    my $targets = $param->{target};
    my $value = $param->{value};
    for my $target (@$targets) {
        my $key = $source . '_' . $target;
        my $sub = $conversions{temperature}->{ $key };
        my $result = $sub->($value);
        my $label = $units{temperature}->{ $target }->{label};
        say "$result$label";
    }
}


sub convert_complete {
    my ($self, $args) = @_;
    my $completion = $args->{completion} or return;
    my $comp_param = $completion->{parameter};
    my $param = $self->parameters;

    if ($comp_param eq 'type') {
        return [keys %units];
    }
    elsif ($comp_param eq 'source') {
        my $type = $param->{type};
        my $units = $units{ $type };
        return [map {
            +{ name => $_, description => $units->{ $_ }->{label} }
        } keys %$units];
    }
    elsif ($comp_param eq 'target') {
        my $type = $param->{type};
        my $source = $param->{source};
        my $value = $param->{value};
        my $units = $units{ $type };
        my @result;
        for my $unit (sort keys %$units) {
            next if $unit eq $source;
            my $label = $units->{ $unit }->{label};
            my $key = $source . '_' . $unit;
            my $sub = $conversions{temperature}->{ $key };
            my $result = $sub->($value);
            push @result, {
                name => $unit,
                description => "$result$label",
            };
        }
        return \@result;
    }
}

1;
