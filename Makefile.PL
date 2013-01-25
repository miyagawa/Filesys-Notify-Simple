use inc::Module::Install;
name 'Filesys-Notify-Simple';
all_from 'lib/Filesys/Notify/Simple.pm';
readme_from 'lib/Filesys/Notify/Simple.pm';
build_requires 'Test::More';
test_requires 'Test::SharedFork';
author_tests('xt');
auto_set_repository;
WriteAll;
