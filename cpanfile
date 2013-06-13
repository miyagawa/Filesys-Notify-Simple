requires 'perl', '5.008001';

on test => sub {
    requires 'Test::More';
    requires 'Test::SharedFork';
    requires 'File::Temp';
};
