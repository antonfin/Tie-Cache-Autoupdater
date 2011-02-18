require 5.8.8;

use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME	    => 'Tie::Cache::Autoupdater',
    VERSION_FROM=> 'Autoupdater.pm',
    AUTHOR      => 'Anton Morozov <anton@antonfin.kiev.ua>',
    ABSTRACT    => 'cache that automatically updated',
    LICENSE     => 'artistic_2',
    test        => { TESTS => 't/*.t' },
);

1;

