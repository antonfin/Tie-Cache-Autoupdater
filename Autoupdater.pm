package Tie::Cache::Autoupdater;

use strict;
use warnings;

our $VERSION = 0.01;

sub TIEHASH {
    my $class       = shift;
    my %structure   = @_;
    
    my $self = {};
    while ( my ($k, $v) = each %structure ) {
        $self->{ $k } = {
            timeout => $v->{timeout} || 1,
            source  => $v->{source},
            last    => 0,
            result  => undef,
        }
    }

    bless $self, $class;
}

sub FETCH { 
    my ( $self, $k ) = @_;
    
    unless ( exists $self->{ $k } ) {
        warn "Key $k doesn't exist\n";
        return undef
    }

    _fetch( $_[0], $k )
}

sub STORE {
    my ( $self, $k, $v ) = @_;
    $self->{ $k } = {
        timeout => $v->{timeout} || 1,
        source  => $v->{source},
        last    => 0,
        result  => undef,
    }
}

sub FIRSTKEY {
    keys %{$_[0]};
    my ( $k, $v ) = each %{$_[0]};
    _fetch( $_[0], $k )
}

sub NEXTKEY  {
    my ( $k, $v ) = each %{$_[0]};
    _fetch( $_[0], $k )
}

sub EXISTS   { exists $_[0]->{ $_[1] } }
sub DELETE   { delete $_[0]->{ $_[1] } }
sub CLEAR    { %{ $_[0] } = () }
sub SCALAR   { scalar %{ $_[0] } }
sub UNTIE    { $_[0] = undef }
sub DESTROY  { }

sub _fetch {
    my ( $self, $k ) = @_;
    
    if ( $self->{$k}{last} + $self->{$k}{timeout} < time ) {

        my @result = eval { $self->{$k}{source}->() };
        if ( $@ ) { 
            warn qq/Check source subroutine for key $k. Error - $@\n/;
            return undef
        }

        if ( @result == 1 ) {
            $self->{$k}{result} = $result[0];
        } elsif ( !@result ) {
            $self->{$k}{result} = undef;
        } else {
            $self->{$k}{result} = \@result;
        }

        $self->{$k}{last} = time;
    }
    
    return $self->{$k}{result}
}

1;

__END__

=head1 NAME

Tie::Cache::Autoupdater - cache that automatically updated 

=head1 VERSION

This documentation refers to <Tie::Cache::Autoupdater> version 0.1

=head1 AUTHOR

<Anton Morozov>  (<anton@antonfin.kiev.ua>)

=head1 SYNOPSIS

        use Tie::Cache::Autoupdate;

        tie my %cache, 'Tie::Cache::Autoupdate', 
            key1 => { source => sub { ....; return $ref },  timeout => 10 },
            key2 => { source => \&get_data_from_db,         timeout => 30 },
            key2 => { source => \&get_data_from_file,       timeout => 60 };

        my ( $data1, $data2, $data3 );

        $data1 = $cache{key1};   # data, that return anonymous subroutine
        $data2 = $cache{key2};   # data, that return get_data_from_db
        $data3 = $cache{key3};   # data, that return get_data_from_file

        ##########################     2 seconds ago    #######################

        $data1 = $cache{key1};   # update data, call anonymous subroutine
        $data2 = $cache{key2};   # old data, nothing called
        $data3 = $cache{key3};   # old data, nothing called

        ##########################     15 seconds ago    ######################

        $data1 = $cache{key1};   # update data, call anonymous subroutine
        $data2 = $cache{key2};   # update data, call get_data_from_db
        $data3 = $cache{key3};   # old data, nothing called

        ##########################    1 minute 10 seconds ago    ##############

        $data1 = $cache{key1};   # update data, call anonymous subroutine one more
        $data2 = $cache{key2};   # update data, call get_data_from_db
        $data3 = $cache{key3};   # update data, call get_data_from_file

=head1 DESCRIPTION

Sometimes I need show in web rarely changes data. You may save it in memory, 
but you never don't know how long script will be work. For example, fcgi scripts
may work few days or weeks, but counters of database tables or site settings may 
changed more frequent in the day, each hour or each 10 minutes. I wrote package,
that help you cached data on fixed time.

=head2 How to use

You may created hash and tied it usages this package.

        tie my %cache, 'Tie::Cache::Autoupdater';

And set it hash

        $cache{key1} = {
            timeout => 10,
            source  => sub { 
                my $sth = $DBH->prepare('select * from table'); 
                $sth->execute;
                return $sth->fetchall_arrayref
            }
        };

Package call anonymous subroutine when you want get value of C<%cache> with key 
C<key1>.
        
Or you may set cache parameters when you tied hash. Like this:

        tie %cache, 'Tie::Cache::Autoupdater', key1 => {
            timeout => 10,
            source  => sub { 
                my $sth = $DBH->prepare('select * from table'); 
                $sth->execute;
                return $sth->fetchall_arrayref
            }
        };


=head2 Parameters

You may set unlimited pairs key => value, where key is unique cache key. Value is
hash reference, where:

=head3 timeout

It's time for data saving

=head3 source

Subroutine reference that return data for cache

=head2 NOTE

If source subroutine return list, that package automatically convert it in array
reference.

=head1 LICENSE AND COPYRIGHT

    Copyright (c) 2011 (anton@antonfin.kiev.ua)

    This program is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself.

=cut

