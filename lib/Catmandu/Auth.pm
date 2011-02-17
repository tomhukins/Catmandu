package Catmandu::Auth;
# VERSION
use 5.010;
use Moose;
use MooseX::Aliases;
use Catmandu::Err;
use Plack::Util;
use Plack::Request;

my $SESSION_KEY = "catmandu.auth";

has app => (
    is => 'bare',
    required => 1,
    handles => [qw(
        default_strategies
        default_scope
        strategies
        scopes
        from_session
        into_session
    )],
);

has env => (
    is => 'ro',
    isa => 'HashRef',
    required => 1,
);

has request => (
    is => 'ro',
    isa => 'Plack::Request',
    alias => 'req',
    lazy => 1,
    default => sub { Plack::Request->new($_[0]->env) },
);

has [qw(_cached_strategies _winning_strategies _users)] => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { +{} },
    init_arg => undef,
);

has _winning_strategy => (
    is => 'rw',
    init_arg => undef,
);

sub logout {
    my ($self, @scopes) = @_;
    my $all = !@scopes;

    if ($all) {
        push @scopes, keys %{$self->_users};
    }

    for my $scope (@scopes) {
        delete $self->session->{"$SESSION_KEY.$scope.session"};
        delete $self->session->{"$SESSION_KEY.$scope.key"};
        delete $self->_users->{$scope};
    }

    if ($all) {
        $self->clear_session;
    }
}

sub login {
    my ($self, $user, %opts) = @_;
    my $scope = $opts{scope} ||= $self->default_scope;

    if (my $default_opts = $self->scopes->{$scope}) {
        while (my ($key, $value) = each %$default_opts) {
            $opts{$key} //= $value;
        }
    }

    $self->_users->{$scope} = $user;

    if ($opts{store}) {
        $self->session->{"$SESSION_KEY.$scope.key"} = $self->into_session->($user);
    }

    $user;
}

sub user {
    my ($self, $scope) = @_;
    $scope ||= $self->default_scope;

    $self->_users->{$scope} ||= do {
        my $session_key = "$SESSION_KEY.$scope.key";
        my $key = $self->session->{$session_key};

        my $user;

        if ($key and $user = $self->from_session->($key)) {
            $self->login($user, scope => $scope)
        }

        if (! $user) {
            delete $self->session->{$session_key};
        }

        $user
    };
}

sub user_session {
    my ($self, $scope) = @_;
    $scope ||= $self->default_scope;
    $self->authenticated($scope) || return;
    $self->session->{"$SESSION_KEY.$scope.session"} ||= {};
}

sub message {
    my $self = shift;
    if ($self->_winning_strategy) {
        return $self->_winning_strategy->message;
    }
    return;
}

sub result {
    my $self = shift;
    if ($self->_winning_strategy) {
        return $self->_winning_strategy->result;
    }
    return;
}

sub custom_response {
    my $self = shift;
    if ($self->_winning_strategy) {
        return $self->_winning_strategy->custom_response;
    }
    return;
}

sub needs_authentication {
    my $self = shift;
    $self->authenticate(@_) || Catmandu::HTTPErr->throw(401);
}

sub authenticated {
    my ($self, $scope) = @_;
    $scope ||= $self->default_scope;
    defined $self->user($scope);
}

sub authenticate {
    my ($self, %opts) = @_;
    my $scope = $opts{scope} ||= $self->default_scope;

    $opts{strategies} ||= $self->scopes->{$scope}{strategies} || $self->default_strategies;

    my $user = $self->user($scope);

    if ($user) {
        return $user;
    }

    $self->_run_strategies(%opts);

    if ($self->_winning_strategy and $user = $self->_winning_strategy->user) {
        $opts{store} ||= $self->_winning_strategy->store;
        $self->login($user, %opts);
    }

    $self->_users->{$scope};
}

sub _run_strategies {
    my ($self, %opts) = @_;
    my $scope = $opts{scope};

    $self->_winning_strategy($self->_winning_strategies->{$scope});

    return if $self->_winning_strategy && 
            $self->_winning_strategy->halts;

    for my $key (@{$opts{strategies}}) {
        my $strategy = $self->_get_strategy($key, $scope);
        return if ! $strategy || $strategy->has_run || ! $strategy->can_authenticate;
        $self->_winning_strategies->{$scope} = $strategy;
        $self->_winning_strategy($strategy);
        $strategy->run;
        last if $strategy->halts;
    }
}

sub _get_strategy {
    my ($self, $key, $scope) = @_;
    $self->_cached_strategies->{$scope}{$key} ||= do {
        my $class = "Catmandu::Auth::Strategies::" . ucfirst($key);
        Catmandu::Util::load_class($class);
        my $attrs = $self->strategies->{$key} || {};
        $class->new(%$attrs, env => $self->env, scope => $scope);
    };
}

sub session {
    $_[0]->env->{'psgix.session'};
}

sub clear_session {
    my $session = $_[0]->env->{'psgix.session'} or return;
    for my $key (keys %$session) {
        delete $session->{$key};
    }
    $session;
}

__PACKAGE__->meta->make_immutable;

no MooseX::Aliases;
no Moose;

1;

