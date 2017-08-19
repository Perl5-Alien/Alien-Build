use Test2::V0 -no_srand => 1;
use Test2::Mock;
use lib 'corpus/lib';
use Env qw( @PKG_CONFIG_PATH );
use File::Glob qw( bsd_glob );
use File::chdir;
use Path::Tiny qw( path );
use FFI::CheckLib;

my $mock = Test2::Mock->new(
  class => 'FFI::CheckLib',
  override => [
    find_lib => sub {
      my %args = @_;
      if($args{libpath})
      {
        return unless -d $args{libpath};
        return sort do {
          local $CWD = $args{libpath};
          map { path($_)->absolute->stringify } bsd_glob('*.so*');
        };
      }
      else
      {
        if($args{lib} eq 'foo')
        {
          return ('/usr/lib/libfoo.so', '/usr/lib/libfoo.so.1');
        }
        else
        {
          return;
        } 
      }
    },
  ],
);


unshift @PKG_CONFIG_PATH, path('corpus/pkgconfig')->absolute->stringify;

subtest 'AB::MB sys install' => sub {

  skip_all 'test requires Alien::Base::PkgConfig'
    unless eval { require Alien::Base::PkgConfig; 1 };

  require Alien::Foo1;

  my $cflags  = Alien::Foo1->cflags;
  my $libs    = Alien::Foo1->libs;
  my $version = Alien::Foo1->version;

  $libs =~ s{^\s+}{};

  is $cflags, '-DFOO=stuff', "cflags: $cflags";
  is $libs,   '-lfoo1', "libs: $libs";
  is $version, '3.99999', "version: $version";
};

sub extract_flag {
  my ($string, $flag) = @_;
  return unless my @matches = $string =~ /(?:\A|\G| )-$flag(.*?)(?:(?<!\\) |\z)/g;
  @matches = map { my $i = $_; $i =~ s#\\ # #g; $i } @matches; # de-quote all quoted spaces
  return wantarray ? @matches : $matches[0];
}

subtest 'AB::MB share install' => sub {

  skip_all 'test requires Alien::Base::PkgConfig'
    unless eval { require Alien::Base::PkgConfig; 1 };

  require Alien::Foo2;

  my $cflags  = Alien::Foo2->cflags;
  my $libs    = Alien::Foo2->libs;
  my $version = Alien::Foo2->version;
    
  ok $cflags,  "cflags: $cflags";
  ok $libs,    "libs:   $libs";
  is $version, '3.2.1', "version: $version";

  if(my $i = extract_flag($cflags, 'I'))
  {
    ok -f "$i/foo2.h", "include path: $i";
  }
  else
  {
    fail "include path: ?";
  }
  
  if(my $i = extract_flag($libs, 'L'))
  {
    ok -f "$i/libfoo2.a", "lib path: $i";
  }
  else
  {
    fail "lib path: ?";
  }

};

subtest 'Alien::Build system' => sub {

  require Alien::libfoo1;
  
  is( -f path(Alien::libfoo1->dist_dir)->child('_alien/for_libfoo1'), T(), 'dist_dir');
  is( Alien::libfoo1->cflags, '-DFOO=1', 'cflags' );
  is( Alien::libfoo1->cflags_static, '-DFOO=1 -DFOO_STATIC=1', 'cflags_static');
  is( Alien::libfoo1->libs, '-lfoo', 'libs' );
  is( Alien::libfoo1->libs_static, '-lfoo -lbar -lbaz', 'libs_static' );
  is( Alien::libfoo1->version, '1.2.3', 'version');
  
  subtest 'install type' => sub {
    is( Alien::libfoo1->install_type, 'system' );
    is( Alien::libfoo1->install_type('system'), T() );
    is( Alien::libfoo1->install_type('share'), F() );
  };
  
  is( Alien::libfoo1->config('name'), 'foo', 'config.name' );
  is( Alien::libfoo1->config('finished_installing'), T(), 'config.finished_installing' );

  is( [Alien::libfoo1->dynamic_libs], ['/usr/lib/libfoo.so','/usr/lib/libfoo.so.1'], 'dynamic_libs' );
  
  is( [Alien::libfoo1->bin_dir], [], 'bin_dir' );
  
  is( Alien::libfoo1->runtime_prop->{arbitrary}, 'one', 'runtime_prop' );
};

subtest 'Alien::Build share' => sub {

  require Alien::libfoo2;
  
  is( -f path(Alien::libfoo2->dist_dir)->child('_alien/for_libfoo2'), T(), 'dist_dir');
  
  subtest 'cflags' => sub {
    my $cflags = Alien::libfoo2->cflags;
    my $dir = extract_flag($cflags, 'I');
    like $dir, qr/include$/, 'cflags';
    my $def = extract_flag($cflags, 'D');
    is $def, 'FOO=1', 'cflags';
    is(
      -f path($dir)->child('foo.h'),
      T(),
      '-I directory points to foo.h location',
    );

    $cflags = Alien::libfoo2->cflags_static;
    $dir = extract_flag($cflags, 'I');
    like $dir, qr/include$/, 'cflags';
    is(
      [extract_flag($cflags, 'D')],
      array {
        item 'FOO=1';
        item 'FOO_STATIC=1';
        end;
      },
      'cflags_static',
    );
    is(
      -f path($dir)->child('foo.h'),
      T(),
      '-I directory points to foo.h location (static)',
    );
  };
  
  subtest 'libs' => sub {
    my $libs = Alien::libfoo2->libs;
    my $dir = extract_flag($libs, 'L');
    like $dir, qr/lib$/, 'libs';
    like extract_flag($libs, 'l'), qr/foo$/, 'libs';
    is(
      -f path($dir)->child('libfoo.a'),
      T(),
      '-L directory points to libfoo.a location',
    );

    $libs = Alien::libfoo2->libs_static;
    $dir = extract_flag($libs, 'L');
    like $dir, qr/lib$/, 'libs';
    is(
      [extract_flag($libs, 'l')],
      array {
        item 'foo';
        item 'bar';
        item 'baz';
        end;
      },
      'libs_static',
    );
    is(
      -f path($dir)->child('libfoo.a'),
      T(),
      '-L directory points to libfoo.a location (static)',
    );
  
  };
  
  is( Alien::libfoo2->version, '2.3.4', 'version' );
  
  subtest 'install type' => sub {
    is( Alien::libfoo2->install_type, 'share' );
    is( Alien::libfoo2->install_type('system'), F() );
    is( Alien::libfoo2->install_type('share'), T() );
  };
  
  is( Alien::libfoo2->config('name'), 'foo', 'config.name' );
  is( Alien::libfoo2->config('finished_installing'), T(), 'config.finished_installing' );
  
  is(
    [Alien::libfoo2->dynamic_libs],
    array {
      item match qr/libfoo.so$/;
      item match qr/libfoo.so.2$/;
      end;
    },
    'dynamic_libs',
  );
  
  is(
    [Alien::libfoo2->bin_dir],
    array {
      item T();
      end;
    },
    'bin_dir',
  );
  
  is( -f path(Alien::libfoo2->bin_dir)->child('foo-config'), T(), 'has a foo-config');
  
  is( Alien::libfoo2->runtime_prop->{arbitrary}, 'two', 'runtime_prop' );

};

subtest 'build flags' => sub {

  my %unix_flags = (
    q{ -L/a/b/c -lz -L/a/b/c } => [ "-L/a/b/c", "-lz", "-L/a/b/c" ],
  );

  my %win_flags = (
    q{ -L/a/b/c -lz -L/a/b/c } => [ "-L/a/b/c", "-lz", "-L/a/b/c" ],
    q{ -LC:/a/b/c -lz -L"C:/a/b c/d" } => [ "-LC:/a/b/c", "-lz", "-LC:/a/b c/d" ],
    q{ -LC:\a\b\c -lz } => [ q{-LC:\a\b\c}, "-lz" ], 
  );

  subtest 'unix' => sub {
    while ( my ($flag, $split) = each %unix_flags ) {
      is( [ Alien::Base->split_flags_unix( $flag ) ], $split );
    }
  };

  subtest 'windows' => sub {
    while ( my ($flag, $split) = each %win_flags ) {
      is( [ Alien::Base->split_flags_windows( $flag ) ], $split );
    }
  };

};

done_testing;
