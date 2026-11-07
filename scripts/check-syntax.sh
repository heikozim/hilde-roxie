#!/usr/bin/env bash
# Every example of docs/syntax.md is a test: the queries of its two
# tables of examples, with their lines or their byte, are the found and
# refused calls of src/Roxie/Find.test.hiq, the same in the same order.  The
# help page (src/Roxie/templates/help.jinja) shows only those: each of its
# examples is a query of the found table and links to the same query, and its
# refused queries are those of the table, with their bytes, in that order.
# Run from the root of the ROXIE tree; the last line says how many it
# compared.
#
#     bash scripts/check-syntax.sh
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "ABORT: bash ${BASH_VERSION} too old" >&2; exit 9; }
set -u
command -v perl > /dev/null 2>&1 || { echo "ABORT: perl not in PATH -- nothing ran" >&2; exit 9; }
[ -r docs/syntax.md ] && [ -r src/Roxie/Find.test.hiq ] && [ -r src/Roxie/templates/help.jinja ] || { echo "ABORT: run from the root of the ROXIE tree" >&2; exit 9; }
perl -CSD -Mutf8 -e '
use strict; use warnings;
my ($doc, $test, $help) = @ARGV;
local $/;
open my $d, "<:encoding(UTF-8)", $doc or die; my $md = <$d>; close $d;
open my $t, "<:encoding(UTF-8)", $test or die; my $hiq = <$t>; close $t;
open my $h, "<:encoding(UTF-8)", $help or die; my $page = <$h>; close $h;
my (@docFound, @docRefused);
my ($found) = $md =~ /\nQueries that find lines:\n\n(.*?)\n\n/s or die "syntax.md: no table of queries that find lines\n";
my ($refused) = $md =~ /\nQueries that are refused, with the byte where \(counted from 0\):\n\n(.*?)\n\n/s or die "syntax.md: no table of refused queries\n";
for (split /\n/, $found) { next unless /^\| `(.*)` \| (\d+) \|$/; push @docFound, "$1 => $2"; }
for (split /\n/, $refused) { next unless /^\| `(.*)` \| (\d+) \| .* \|$/; push @docRefused, "$1 => $2"; }
my (@testFound, @testRefused);
sub unq { my $s = shift; $s =~ s/\\"/"/g; $s =~ s/\\\\/\\/g; return $s; }
while ($hiq =~ /^        found\(&~db, "((?:[^"\\]|\\.)*)", (\d+)\);$/mg) { push @testFound, unq($1) . " => $2"; }
while ($hiq =~ /^        refused\(&~db, "((?:[^"\\]|\\.)*)", (\d+)\);$/mg) { push @testRefused, unq($1) . " => $2"; }
my $bad = 0;
sub same { my ($what, $a, $b) = @_; my $n = @$a > @$b ? @$a : @$b; for my $i (0 .. $n - 1) { my $x = $a->[$i] // "(none)"; my $y = $b->[$i] // "(none)"; next if $x eq $y; print "differ  $what $i: syntax.md $x, test $y\n"; $bad++; } }
same("found", \@docFound, \@testFound);
same("refused", \@docRefused, \@testRefused);
die "syntax.md: no examples\n" unless @docFound and @docRefused;
sub unhtml { my $s = shift; $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g; $s =~ s/&quot;/"/g; $s =~ s/&#34;/"/g; $s =~ s/&amp;/&/g; return $s; }
my %known = map { /^(.*) => \d+$/ ? ($1 => 1) : () } @docFound;
my $helpFound = 0;
while ($page =~ m{<a href="/search\?q=([^"]*)"><code>(.*?)</code></a>}g) {
	my ($link, $shown) = ($1, unhtml($2));
	(my $query = $link) =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge;
	$helpFound++;
	if ($query ne $shown) { print "differ  help: the link of $shown is $query\n"; $bad++; }
	if (!$known{$shown}) { print "differ  help: $shown is no example of syntax.md\n"; $bad++; }
}
my @helpRefused;
while ($page =~ m{<tr class="roxie-refused"><td><code>(.*?)</code></td><td>(\d+)</td>}g) { push @helpRefused, unhtml($1) . " => $2"; }
same("help refused", \@docRefused, \@helpRefused);
die "help.jinja: no examples\n" unless $helpFound and @helpRefused;
printf "syntax: found=%d refused=%d help-found=%d help-refused=%d differ=%d\n", scalar @docFound, scalar @docRefused, $helpFound, scalar @helpRefused, $bad;
exit($bad ? 1 : 0);
' docs/syntax.md src/Roxie/Find.test.hiq src/Roxie/templates/help.jinja
