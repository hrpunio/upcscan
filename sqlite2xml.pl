#!/usr/bin/perl -w
use DBI;
use strict;
my $db = DBI->connect("dbi:SQLite:personal_catalog.dat", "", "",
   {RaiseError => 1, AutoCommit => 1});

# http://mailliststock.wordpress.com/2007/03/01/sqlite-examples-with-bash-perl-and-python/
my $sth = $db->prepare("SELECT description FROM works");
$sth->execute();

print "<?xml version='1.0' ?>\n";
print "<catalog>\n";
my $r__ = 0;

while (my @data = $sth->fetchrow_array()) { print  $data[0], "\n"; $r__++; }

print "</catalog>\n";
print STDERR "*** $r__ records printed! ***\n";

##
