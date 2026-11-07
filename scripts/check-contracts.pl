#!/usr/bin/env perl
# Every function and method declared in a .hih, between "module X is" and
# "end module.", states a contract (a requires or ensures clause before the
# semicolon that ends its declaration) or names why it has none: a line
# "No contract: <reason>." in the docstring before it.  Prints file:line
# and the name of every declaration that does neither; exit 1 on any, 0
# when there is none, 2 on a file that cannot be read.
#
#     perl scripts/check-contracts.pl src app
#     perl scripts/check-contracts.pl --self-test
use strict;
use warnings;
use File::Find;

# The misses of one interface text, as "line name" pairs.
sub misses {
	my ($text) = @_;
	my @out;
	my @lines = split /\n/, $text, -1;
	my ($inside, $doc, $indoc, $reason) = (0, '', 0, 0);
	for (my $i = 0; $i < @lines; $i++) {
		my $l = $lines[$i];
		if (!$inside) {
			$inside = 1 if $l =~ /^module\s+\S+\s+is\b/;
			next;
		}
		last if $l =~ /^end module\./;
		if ($indoc) {
			$reason = 1 if $l =~ /^\s*No contract: \S/;
			$indoc = 0 if $l =~ /"""/;
			next;
		}
		if ($l =~ /^\s*"""(.*)$/) {
			my $rest = $1;
			$reason = $rest =~ /^\s*No contract: \S/ ? 1 : 0;
			$indoc = 1 unless $rest =~ /"""/;
			next;
		}
		if ($l =~ /^\s*(function|method)\s+([A-Za-z_][A-Za-z0-9_]*)/) {
			my ($at, $name, $decl) = ($i + 1, $2, '');
			for (; $i < @lines; $i++) {
				$decl .= "$lines[$i]\n";
				last if $lines[$i] =~ /;/;
			}
			push @out, "$at $name" unless $decl =~ /\b(requires|ensures)\b/ || $reason;
			$reason = 0;
			next;
		}
		# A declaration of another kind ends what the docstring said.
		$reason = 0 if $l =~ /;\s*$/;
	}
	return @out;
}

sub self_test {
	my $head = "module M is\n";
	my $tail = "end module.\n";
	my @cases = (
		["bare", "    function f(x: Int64): Int64;\n", 1],
		["requires", "    function f(x: Int64): Int64\n        requires x > 0;\n", 0],
		["ensures inline", "    function f(): Int64 ensures result = 3;\n", 0],
		["reason", "    \"\"\"\n    F.\n\n    No contract: the answer is the work of the database.\n    \"\"\"\n    function f(): Int64;\n", 0],
		["reason one line", "    \"\"\"No contract: it only consumes.\"\"\"\n    function f(): Int64;\n", 0],
		["reason of the one before", "    \"\"\"\n    No contract: a reason.\n    \"\"\"\n    function f(): Int64;\n    function g(): Int64;\n", 1],
		["generic method", "    generic [R: Region]\n    method m(x: &[T, R]): Unit;\n", 1],
		["empty reason", "    \"\"\"\n    No contract:\n    \"\"\"\n    function f(): Int64;\n", 1],
		["outside the module", "", 0, "function f(): Int64;\n"],
	);
	my $good = 0;
	for my $c (@cases) {
		my ($what, $body, $want, $before) = @$c;
		my @m = misses(($before // '') . $head . $body . $tail);
		if (scalar(@m) == $want) {
			$good++;
		} else {
			print "FAIL self-test $what: " . scalar(@m) . " misses, want $want\n";
		}
	}
	print "self-test good=$good of " . scalar(@cases) . "\n";
	return $good == @cases ? 0 : 1;
}

if (@ARGV == 1 && $ARGV[0] eq '--self-test') {
	exit self_test();
}
@ARGV or die "usage: check-contracts.pl <tree>... | --self-test\n";
my @files;
for my $tree (@ARGV) {
	-d $tree or die "ABORT: no directory $tree\n";
	find({ no_chdir => 1, wanted => sub { push @files, $_ if /\.hih$/ && -f $_ && !/\/\._/ } }, $tree);
}
my ($decls, $miss) = (0, 0);
for my $f (sort @files) {
	open my $fh, '<', $f or do { print "ABORT: cannot read $f\n"; exit 2; };
	local $/;
	my $text = <$fh>;
	close $fh;
	$decls += () = $text =~ /^\s*(?:function|method)\s+[A-Za-z_]/mg;
	for my $m (misses($text)) {
		my ($line, $name) = split / /, $m;
		print "$f:$line $name\n";
		$miss++;
	}
}
print "contract-lint files=" . scalar(@files) . " declarations=$decls missed=$miss\n";
exit($miss ? 1 : 0);
