package Test::Lazy::Tester;

use warnings;
use strict;

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(qw/render cmp_scalar cmp_structure/);

use Data::Dumper qw/Dumper/;
use Carp;
use Test::Deep;
use Test::Builder();
use B::Deparse;

my $deparser = B::Deparse->new;
$deparser->ambient_pragmas(strict => 'all', warnings => 'all');

my %base_cmp_scalar = (
	ok => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::More::ok($_[0], $_[2])
    },

	not_ok => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::More::ok(! $_[0], $_[2])
    },

	(map { my $mtd = $_; $_ => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::More::cmp_ok($_[0] => $mtd => $_[1], $_[2])
    } }
	qw/< > <= >= lt gt le ge == != eq ne/),

	(map { my $method = $_; $_ => sub {
        no strict 'refs';
        local $Test::Builder::Level = $Test::Builder::Level + 1;
       "Test::More::$method"->($_[0], $_[1], $_[2])
    } }
	qw/is isnt like unlike/),
);

my %base_cmp_structure = (
	ok => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::More::ok($_[0], $_[2])
    },

	not_ok => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::More::ok(! $_[0], $_[2])
    },

    (map { $_ => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::Deep::cmp_bag($_[0], $_[1], $_[2]);
    } }
    qw/bag same_bag samebag/),

    (map { $_ => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::Deep::cmp_set($_[0], $_[1], $_[2]);
    } }
    qw/set same_set sameset/),

    (map { $_ => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::Deep::cmp_deeply($_[0], $_[1], $_[2]);
    } }
    qw/same is like eq ==/),

	(map { $_ => sub {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        Test::More::ok(!Test::Deep::eq_deeply($_[0], $_[1]), $_[2]);
    } }
    qw/isnt unlink ne !=/),
);

my %base_render = (
    ARRAY => sub {
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Varname = 0;
        local $Data::Dumper::Terse = 1;
        my $self = shift;
        my $value = shift;
        return Dumper($value);
    },

    HASH => sub {
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Varname = 0;
        local $Data::Dumper::Terse = 1;
        my $self = shift;
        my $value = shift;
        return Dumper($value);
    },

    undef => sub {
        return "undef";
    },
);

sub new {
    my $self = bless {}, shift;
    local %_ = @_;
    $self->{cmp_scalar} = { %base_cmp_scalar, %{ $_{cmp_scalar} || {} } };
    $self->{cmp_structure} = { %base_cmp_structure, %{ $_{cmp_structure} || {} } };
    $self->{render} = { %base_render, %{ $_{base_render} || {} } };
    return $self;
}

sub _render_notice {
    my $self = shift;
    my ($left, $compare, $right, $notice) = @_;

	my $_notice = "$left $compare $right";
	if (defined $notice) {
        # TODO Do %% escaping
		$notice =~ s/%/$_notice/;
	}
	else {
		$notice = $_notice;
	}

    return $notice;
}

sub _render_value {
    my $self = shift;
	my $value = shift;

    my $type = ref $value;
    $type = "undef" unless defined $value;

    return $value unless $type;
    return $value unless my $renderer = $self->render->{$type};
    return $renderer->($self, $value);
}

sub _test {
    my $self = shift;
	my ($compare, $got, $expect, $notice) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $cmp = $compare;
	if (ref $cmp eq "CODE") {
		Test::More::ok($cmp->($got, $expect), $notice);
	}
	else {
        my $structure = ref $expect eq "ARRAY" || ref $expect eq "HASH";
        my $scalar = ! $structure;

        my $cmp_source = $scalar ? $self->cmp_scalar : $self->cmp_structure;

		croak "Don't know how to compare via ($compare)" unless $cmp = $cmp_source->{$cmp};
		$cmp->($got, $expect, $notice);
	}
}

sub check {
    my $self = shift;
	my ($got, $compare, $expect, $notice) = @_;

	my $left = $self->_render_value($got);
	my $right = $self->_render_value($expect);
    $notice = $self->_render_notice($left, $compare, $right, $notice);

	return $self->_test($compare, $got, $expect, $notice);
}

sub try {
    my $self = shift;
	my ($statement, $compare, $expect, $notice) = @_;

	my @got = ref $statement eq "CODE" ? $statement->() : eval $statement;
	die "$statement: $@" if $@;
	my $got;
	if (@got > 1) {
		if (ref $expect eq "ARRAY") {
			$got = \@got;
		}
		elsif (ref $expect eq "HASH") {
			$got = { @got };
		}
		else {
			$got = scalar @got;
		}
	}
	else {
		if (ref $expect eq "ARRAY" && (! @got || ref $got[0] ne "ARRAY")) {
			$got = \@got;
		}
		elsif (ref $expect eq "HASH" && ! @got) {
			$got = { };
		}
		else {
			$got = $got[0];
		}
	}
	
    my $left;
	if (ref $statement eq "CODE") {
		my $deparse = $deparser->coderef2text($statement);
		my @deparse = split m/\n\s*/, $deparse;
		$deparse = join ' ', "sub", @deparse if 3 == @deparse;
		$left = $deparse;
	}
	else {
		$left = $statement;
	}
	my $right = $self->_render_value($expect);
    $notice = $self->_render_notice($left, $compare, $right, $notice);

    local $Test::Builder::Level = $Test::Builder::Level + 1;

	return $self->_test($compare, $got, $expect, $notice);
}

sub template {
    my $self = shift;
    require Test::Lazy::Template;
	return Test::Lazy::Template->new($self, @_);
}

1;
