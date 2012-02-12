#!perl -T

use 5.008;
use strict;
use warnings;
use utf8;
use Test::More;


BEGIN {
  eval { require DBD::SQLite; 1 }
    or plan skip_all => 'DBD::SQLite required';
  eval { DBD::SQLite->VERSION >= 1 }
    or plan skip_all => 'DBD::SQLite >= 1.00 required';
}
use DBIx::Simple::Class;
my $DSCLASS = 'DBIx::Simple::Class';

# In memory database! No file permission troubles, no I/O slowness.
# http://use.perl.org/~tomhukins/journal/31457 ++

my $dbix = DBIx::Simple->connect('dbi:SQLite:dbname=:memory:', {sqlite_unicode => 1});

#$DSCLASS->DEBUG(1);
is($DSCLASS->DEBUG,    0);
is($DSCLASS->DEBUG(1), 1);
is($DSCLASS->DEBUG(0), 0);
like((eval { $DSCLASS->dbix }, $@), qr/not instantiated/);
like((eval { $DSCLASS->dbix('') }, $@), qr/not instantiated/);
isa_ok(ref($DSCLASS->dbix($dbix)), 'DBIx::Simple');
isa_ok(ref($DSCLASS->dbix),        'DBIx::Simple');

like((eval { $DSCLASS->TABLE },   $@), qr/tablename for your class/);
like((eval { $DSCLASS->COLUMNS }, $@), qr/fields for your class/);
like((eval { $DSCLASS->CHECKS },  $@), qr/define your CHECKS subroutine/);
is(ref($DSCLASS->WHERE), 'HASH');

my $groups_table = <<"T";
CREATE TABLE groups(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  `group` VARCHAR(12)
  )
T
my $users_table = <<"T";
CREATE TABLE users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INT default 1,
  login_name VARCHAR(12),
  login_password VARCHAR(100), 
  disabled INT DEFAULT 1
  )
T

$dbix->query($groups_table);
$dbix->query($users_table);

{

  package My::Group;


  1;
}

{

  package My::User;
  use base qw(DBIx::Simple::Class);

  sub TABLE   {'users'}
  sub COLUMNS { [qw(id group_id login_name login_password disabled)] }
  sub WHERE   { {disabled => 1} }

  #See Params::Check
  my $_CHECKS = {
    id       => {allow => qr/^\d+$/x},
    group_id => {allow => qr/^\d+$/x, default => 1},
    disabled => {
      default => 1,
      allow   => sub {
        return $_[0] =~ /^[01]$/x;
        }
    },
    login_name     => {allow => qr/^\p{IsAlnum}{4,12}$/x},
    login_password => {
      required => 1,
      allow    => sub { $_[0] =~ /^[\w\W]{8,20}$/x; }
      }

      #...
  };
  sub CHECKS {$_CHECKS}

  sub id {
    my ($self, $value) = @_;
    if (defined $value) {    #setting value
      $self->{data}{id} = $self->_check(id => $value);

      #make it chainable
      return $self;
    }
    $self->{data}{id} //= $self->CHECKS->{id}{default};    #getting value
  }
  1;
}

#$DSCLASS->DEBUG(1);
isa_ok(ref(My::User->dbix),        'DBIx::Simple');
isa_ok(ref(My::User->dbix($dbix)), 'DBIx::Simple');
is(My::User->TABLE, 'users');
is_deeply(My::User->COLUMNS, [qw(id group_id login_name login_password disabled)]);
is(ref(My::User->WHERE), 'HASH');
is_deeply(My::User->WHERE, {disabled => 1});
my $user;
my $password = time;
like(
  (eval { $user = My::User->new() }, $@),
  qr/Required option/,
  '"Required option" ok'
);


ok($user = My::User->new(login_password => $password));

like(
  (eval { $user->_make_field_attrs() }, $@),
  qr/Call this method as/,
  '_make_field_attrs() ok'
);

isa_ok(ref($user), $DSCLASS);

#defaults
is($user->id, undef, 'id is undefined ok');
is($user->group_id, $user->CHECKS->{group_id}{default}, 'group_id default ok');
delete $user->CHECKS->{group_id}{default};
delete $user->{data}->{group_id};
is($user->group_id, $user->CHECKS->{group_id}{default}, 'group_id default ok');
is($user->login_name, undef, 'login_name is undefined ok');
is($user->login_password, $password, 'login_password is defined ok');
is($user->disabled, $user->CHECKS->{disabled}{default}, 'disabled by default ok');

#invalid
my $type_error = qr/\sis\sof\sinvalid\stype/x;
like((eval { $user->id('bar') },       $@), $type_error, "id is invalid ok");
like((eval { $user->group_id('bar') }, $@), $type_error, "group_id is invalid ok");

like((eval { $user->login_name('sakdk-') }, $@), $type_error, "login_name_error ok");
like((eval { $user->login_name('пет') }, $@),
  $type_error, 'login_name is shorter ok');
like((eval { $user->login_name('петърparvanov') }, $@),
  $type_error, 'login_name is longer ok');

like((eval { $user->login_password('тайнаtа') }, $@),
  $type_error, 'login_password is shorter ok');
like((eval { $user->login_password('тайнаtатайнаtатайнаtа') }, $@),
  $type_error, 'login_password is longer ok');

like((eval { $user->disabled('foo') }, $@), $type_error, 'disabled is invalid ok');
like((eval { $user->disabled(5) },     $@), $type_error, 'disabled is longer ok');

#valid
ok($user->login_name('петър')->login_name, 'login_name is valid');
ok($user->login_password('петър123342%$')->login_password,
  'login_password is valid');
ok($user->disabled(0), 'disabled is valid');
is($user->disabled, 0, 'disabled is valid');

#data
is($user->data->{disabled}, 0, 'disabled via data is valid');
is($user->data('disabled'), 0, 'disabled via data is valid');
is($user->data(disabled => 0, group_id => 2)->{group_id},
  2, 'disabled via data is valid');
is(ref $user->data, 'HASH', 'disabled via data is valid');


{

  package My::Group;
  use base qw(DBIx::Simple::Class);

  sub TABLE {'groups'}
  my $columns = [qw(id group foo-bar)];
  sub COLUMNS {$columns}
  sub WHERE   { {} }

  #See Params::Check
  my $_CHECKS = {};
  sub CHECKS {$_CHECKS}
  1;
}
my $group;
like(
  (eval { My::Group->new() }, $@),
  qr/Illegal declaration of subroutine/,
  '"Illegal declaration of subroutine" ok'
);
delete My::Group->COLUMNS->[-1];
is_deeply(My::Group->COLUMNS, [qw(id group)]);

like(
  (eval { My::Group->new(description => 'tralala') }, $@),
  qr/is not a valid key for/,
  '"is not a valid key for" ok'
);
like(
  (eval { My::Group->new->data('lala') }, $@),
  qr/Can't locate object method "lala" via package "My::Group"/,
  '"is not a valid key for" ok'
);
ok(My::Group->can('id'),    'can id');
ok(My::Group->can('group'), 'can group');
My::Group->DEBUG(1);
ok($group = My::Group->new);
ok($group->id(1));
ok($group->data('lala' => 1));
is_deeply($group->data(), {id => 1}, '"There is not such field lala" ok');
My::Group->DEBUG(0);
done_testing();

