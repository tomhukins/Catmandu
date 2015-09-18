package Catmandu::Cmd::run;

use Catmandu::Sane;
use parent 'Catmandu::Cmd';
use Catmandu;
use Catmandu::Interactive;
use Catmandu::Fix;

sub command_opt_spec {
    (
        [ "verbose|v", "" ],
        [ "i"        , "interactive mode"],
    );
}

sub description {
    <<EOS;
examples:

   # Run an interactive Fix shell

   # Execute the fix script
   \$ catmandu run myfixes.txt

   # Or create an execurable fix script:

   #!/usr/bin/env catmandu run
   do importer(Mock,size:10)
      add_field(foo,bar)
   end

options:
EOS
}

sub command {
    my ($self, $opts, $args) = @_;

    if (defined $opts->{i} || !defined $args->[0]) {
        my $app = Catmandu::Interactive->new();
        $app->run();
    }
    else {
        my $fix_file = $args->[0];
        $fix_file = [\*STDIN] unless defined $fix_file;

        my $from = Catmandu->importer('Null');
        my $into = Catmandu->exporter('Null', fix => $fix_file);

        $from = $from->benchmark if $opts->verbose;
        my $n = $into->add_many($from);
        $into->commit;

        if ($opts->verbose) {
            say STDERR $n == 1 ? "converted 1 object" : "converted $n objects";
            say STDERR "done";
        }
    }
}

1;

=head1 NAME

Catmandu::Cmd::run - run a fix command