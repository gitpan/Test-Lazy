package Test::Lazy;

use warnings;
use strict;

=head1 NAME

Test::Lazy - A quick and easy way to compose and run tests with useful output.

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';

=head1 SYNOPSIS

	use Test::Lazy qw/check try/;

	check(1 => is => 1);
	check(0 => isnt => 1);
	check(a => like => qr/[a-zA-Z]/);
	check(0 => unlike => qr/a-zA-Z]/);
	check(1 => '>' => 0);
	check(0 => '<' => 1);

	try('qw/a/' => eq => 'a');
	try('qw/a/' => ne => 'b');
	try('qw/a/' => is => ['a']);

=cut

BEGIN {
	our @EXPORT_OK = qw/check try template/;
	use base qw/Exporter/;
}

use JSON::XS;
use Test::Builder();
use Test::More();
use Carp;
use B::Deparse;
my $deparser = B::Deparse->new;
$deparser->ambient_pragmas(strict => 'all', warnings => 'all');

use Test::Lazy::Template;
my $Test = Test::Builder->new;

sub _up() { $Test::Builder::Level += 1 }
my %cmpr = (
	ok => sub { _up and Test::More::ok($_[0], $_[2]) },
	not_ok => sub { _up and Test::More::ok(! $_[0], $_[2]) },
	(map { my $mtd = $_; $_ => sub { _up and Test::More::cmp_ok($_[0] => $mtd => $_[1], $_[2]) } }
		qw/< > <= >= lt gt le ge == != eq ne/),
	(map { my $mtd = $_; $_ => sub { no strict 'refs'; _up and "Test::More::$mtd"->($_[0], $_[1], $_[2]) } }
		qw/is isnt like unlike/),
);

sub _expand($) {
	my $value = shift;
	my $xpnd_value = $value;
	$xpnd_value = 'undef' unless defined $value;
	$xpnd_value = to_json($value) if ref $value eq 'ARRAY' || ref $value eq 'HASH';
	return $xpnd_value;
}

sub _test($$$$) {
	my ($cmpr, $value0, $value1, $msg) = @_;

	local $Test::Builder::Level = $Test::Builder::Level ? $Test::Builder::Level + 1 : 1;

	if (ref $cmpr eq "CODE") {
		Test::More::ok($cmpr->($value0, $value1), $msg);
	}
	else {
		croak "Don't know how to compare by ($cmpr)" unless my $cmpr_code = $cmpr{$cmpr};
		$cmpr_code->($value0, $value1, $msg);
	}
}

=over 4

=item try( <stmt>, <cmpr>, <expected>, [ <msg> ] )

Evaluate <stmt> and compare the result to <expected> using <cmpr>.
Optionally provide a <msg> to display on failure. If <msg> is not given,
then one will be automatically made from <stmt>, <cmpr>, and <expected>.

C<try> will also try to guess what representation is best for the result of
the statement, whether that be single value, ARRAY, or HASH. It'll do this based
on what is returned by the statement, and the type of <expected>.
See `perldoc -m Test::Lazy` for more detail.

Note, if <expected> is an ARRAY or HASH, this function will convert it to it's JSON
representation before comparison.

	try("2 + 2" => '==' => 5);

	# This will produce the following output:

	#   Failed test '2 + 2 == 5'
	#   at __FILE__ line __LINE__.
	#          got: '4'
	#     expected: '5'

=cut

sub try {
	my ($stmt, $cmpr, $rslt, $msg) = @_;

	my @value0 = ref $stmt eq "CODE" ? $stmt->() : eval $stmt;
	die "$stmt: $@" if $@;
	my $value0;
	if (@value0 > 1) {
		if (ref $rslt eq "ARRAY") {
			$value0 = \@value0;
		}
		elsif (ref $rslt eq "HASH") {
			$value0 = { @value0 };
		}
		else {
			$value0 = scalar @value0;
		}
	}
	else {
		if (ref $rslt eq "ARRAY" && (! @value0 || ref $value0[0] ne "ARRAY")) {
			$value0 = \@value0;
		}
		elsif (ref $rslt eq "HASH" && ! @value0) {
			$value0 = { };
		}
		else {
			$value0 = $value0[0];
		}
	}
	
	$value0 = _expand $value0;
	my $value1 = _expand $rslt;

	my $_msg;
	if (ref $stmt eq "CODE") {
#		$_msg = "$value1 $cmpr " . $deparser->coderef2text($stmt);
		my $deparse = $deparser->coderef2text($stmt);
#		$deparse =~ s/\n//g if $deparse =~ m/\n/ > 2;
		my @deparse = split m/\n\s*/, $deparse;
		$deparse = join ' ', @deparse if 3 == @deparse;
		$_msg = "$deparse $cmpr $value1";
	}
	else {
		$_msg = "$stmt $cmpr $value1";
	}

	if (defined $msg) {
		$msg =~ s/%/$_msg/;
	}
	else {
		$msg = $_msg;
	}

	local $Test::Builder::Level = $Test::Builder::Level ? $Test::Builder::Level + 1 : 1;

	return _test $cmpr, $value0, $value1, $msg;
}

=item check( <got>, <cmpr>, <expected>, [ <msg> ] )

Compare <got> to <expected> using <cmpr>.
Optionally provide a <msg> to display on failure. If <msg> is not given,
then one will be automatically made from <got>, <cmpr>, and <expected>.

Note, if <got> or <expected> is an ARRAY or HASH, this function will convert them to their JSON
representation before comparison.

	check([qw/a b/] => is => [qw/a b c/]);

	# This will produce the following output:

	#   Failed test '["a","b"] is ["a","b","c"]'
	#   at __FILE__ line __LINE__.
	#         got: '["a","b"]'
	#    expected: '["a","b","c"]'

=cut

sub check {
	my ($value0, $cmpr, $rslt, $msg) = @_;

	$value0 = _expand $value0;
	my $value1 = _expand $rslt;

	my $_msg = "$value0 $cmpr $value1";
	if (defined $msg) {
		$msg =~ s/%/$_msg/;
	}
	else {
		$msg = $_msg;
	}

	return _test $cmpr, $value0, $value1, $msg;
}

=item template( ... ) 

Convenience function for creating a C<Test::Lazy::Template>. All arguments are directly passed to
C<Test::Lazy::Template->new>.

See C<Test::Lazy::Template> for more details.

Returns a new C<Test::Lazy::Template> object.

=cut

sub template {
	return Test::Lazy::Template->new(@_);
}

=back

=head1 cmpr

<cmpr> can be one of the following: 

	ok, not_ok, is, isnt, like, unlike,
	<, >, <=, >=, lt, gt, le, ge, ==, !=, eq, ne,

=head1 AUTHOR

Robert Krimen, C<< <rkrimen at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-test-lazy at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-Lazy>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Test::Lazy

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Test-Lazy>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Test-Lazy>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Test-Lazy>

=item * Search CPAN

L<http://search.cpan.org/dist/Test-Lazy>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2007 Robert Krimen, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Test::Lazy
