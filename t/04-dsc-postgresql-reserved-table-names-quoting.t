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
    or plan skip_all => 'DBD::Pg >= 2.19.3 is required. You have only'
    . $DBD::Pg::VERSION;
  use File::Basename 'dirname';
  use Cwd;
  use lib (Cwd::abs_path(dirname(__FILE__) . '/..') . '/examples/lib');
}
use My;
use My::Window;

local $Params::Check::VERBOSE = 0;

#Suppress some warnings from DBIx::Simple::Class during tests.
local $SIG{__WARN__} = sub {
  warn $_[0] if $_[0] !~ /(generated accessors|is not such field)/;
};


my $DSC = 'DBIx::Simple::Class';

my $dbix;
eval {
  $dbix =
    DBIx::Simple->connect('dbi:Pg:database=test',
    '', '');
}
  or plan skip_all => (
  $@ =~ /Can't connect to local/
  ? 'Start PostgreSQL on localhost to enable this test.'
  : $@
  );

My->dbix($dbix);
isa_ok(ref($DSC->dbix), 'DBIx::Simple');

my $window_table = <<"T";
CREATE TEMPORARY TABLE "window" (
  "id" SERIAL UNIQUE NOT NULL PRIMARY KEY,
  "offset" VARCHAR(12)
  )
T

$dbix->query($window_table);

#$DSC->DEBUG(1);

my $window;
my $offset = time;

ok($window = My::Window->new(offset => $offset));

ok($window->save);

done_testing();
