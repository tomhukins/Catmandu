package Catmandu::Fix::downcase;

use Catmandu::Sane;
use Catmandu::Util qw(:is :data as_utf8);
use Moo;

has path => (is => 'ro', required => 1);
has key  => (is => 'ro', required => 1);

around BUILDARGS => sub {
    my ($orig, $class, $path) = @_;
    my ($p, $key) = parse_data_path($path);
    $orig->($class, path => $p, key => $key);
};

sub fix {
    my ($self, $data) = @_;

    my $key = $self->key;
    for my $match (grep ref, data_at($self->path, $data)) {
        set_data($match, $key,
            map { is_string($_) ? lc(as_utf8($_)) : $_ }
                get_data($match, $key));
    }

    $data;
}

sub emit {
    my ($self, $fixer) = @_;
    my $path_to_key = $self->path;
    my $key = $self->key;

    $fixer->emit_walk_path($fixer->var, $path_to_key, sub {
        my $var = shift;
        $fixer->emit_get_key($var, $key, sub {
            my $var = shift;
            "${var} = lc(as_utf8(${var})) if is_string(${var});";
        });
    });
}

=head1 NAME

Catmandu::Fix::downcase - lowercase the value of a field

=head1 SYNOPSIS

   # Lowercase 'foo'. E.g. foo => 'BAR'
   downcase('foo'); # foo => 'bar'

=head1 SEE ALSO

L<Catmandu::Fix>

=cut

1;
