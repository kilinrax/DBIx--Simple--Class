#!perl

use 5.10.1;
use strict;
use warnings;
use utf8;
use Test::More;

BEGIN {
  eval { require DBD::Pg; 1 }
    or plan skip_all => 'DBD::Pg is required for this test.';
  eval { $DBD::Pg::VERSION >= 2.19.3 }
    or plan skip_all => 'DBD::Pg >= 2.19.3 required. You have only '
    . $DBD::Pg::VERSION;
  use File::Basename 'dirname';
  use Cwd;
  use lib (Cwd::abs_path(dirname(__FILE__) . '/..') . '/examples/lib');
}
use Data::Dumper;
use DBIx::Simple::Class::Schema;


my $DSCS = 'DBIx::Simple::Class::Schema';
my $dbix;
eval {
  $dbix =
    DBIx::Simple->connect('dbi:Pg:dbname=test',
    '', '');
}
  or plan skip_all => (
  $@ =~ /Can\'t connect to local/
  ? 'Start PostgreSQL on localhost to enable this test.'
  : $@
  );

#=pod

#Suppress some warnings from DBIx::Simple::Class during tests.
local $SIG{__WARN__} = sub {
  if (
    $_[0] =~ /(Will\sdump\sschema\sat
         |exists
         |avoid\snamespace\scollisions
         |\w+\.pm|make\spath)/x
    )
  {
    my ($package, $filename, $line, $subroutine) = caller(2);
#    ok($_[0], $subroutine . " warns '$1' OK");
  }
  else {
    warn $_[0];
  }
};

#=cut

isa_ok(ref($DSCS->dbix($dbix)), 'DBIx::Simple');
can_ok($DSCS, qw(load_schema dump_schema_at));


#create some tables
#=pod

$dbix->query('DROP TABLE IF EXISTS "users"');
$dbix->query('DROP TABLE IF EXISTS "groups"');

$dbix->query(<<'TAB');
CREATE TABLE IF NOT EXISTS groups(
  id SERIAL NOT NULL PRIMARY KEY,
  group_name VARCHAR(12),
  "is blocked" BOOLEAN,
  data TEXT
)
TAB

$dbix->query(<<'TAB');
CREATE TABLE IF NOT EXISTS "users" (
  "id" SERIAL NOT NULL PRIMARY KEY,
  "group_id" INTEGER NOT NULL REFERENCES groups(id),
  "login_name" varchar(100) NOT NULL UNIQUE,
  "login_password" varchar(100) NOT NULL UNIQUE,
  "name" varchar(255) NOT NULL DEFAULT '',
  "email" varchar(255) NOT NULL DEFAULT 'email@domain.com',
  "disabled" BOOLEAN NOT NULL DEFAULT FALSE,
  balance DECIMAL(8,2) NOT NULL DEFAULT '0.00',
  dummy_dec DECIMAL(8,0) NOT NULL DEFAULT '0'
)
TAB

#=cut

ok(my $code = $DSCS->load_schema(namespace => 'Test'), 'scalar context OK');
ok(my @code = $DSCS->load_schema(namespace => 'Test'), 'list context OK');

#warn Dumper($DSCS->_schemas('Test')->{tables});
#PARAMS
delete $DSCS->_schemas->{Test};
$DSCS->load_schema(namespace => 'Your::Model', table => '%user%', type => "'TABLE'")
  ;    #void context ok
isa_ok($DSCS->_schemas('Your::Model'),
  'HASH', 'load_schema creates Your::Model namespace OK');

is($DSCS->_schemas('Your::Model')->{tables}[0]->{TABLE_NAME},
  'users', 'first table is "users"');
is(scalar @{$DSCS->_schemas('Your::Model')->{tables}}, 1, 'the only table is "users"');
SKIP: {
  skip "I have only linux, see http://perldoc.perl.org/perlport.html#chmod", 1,
    if $^O !~ /linux/i;
  chmod 0444, $INC[0];
  ok(!$DSCS->dump_schema_at(lib_root => $INC[0]), 'quits OK');
  chmod 0755, $INC[0];
}
ok($DSCS->dump_schema_at(lib_root => $INC[0]), 'dumps OK');
File::Path::remove_tree($INC[0] . '/Your');
$dbix->query('DROP TABLE IF EXISTS "users"');
$dbix->query('DROP TABLE IF EXISTS "groups"');

done_testing;

