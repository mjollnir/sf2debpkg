
# This is very much based on the work found here:
# http://www.perlmonks.org/?node_id=813726
# But with multiple-merge key support as well.

package Liip::YAML;

use strict;
use warnings;


sub multi_mergekeys
{
    my ($orig) = @_;
    while (my $ref = shift)
    {
        my $type = ref $ref;
        if ($type eq 'HASH')
        {
            my $tmphref = $ref->{'<<'};
            if ($tmphref)
            {
                if (ref $tmphref eq 'ARRAY') {
                    foreach my $multi (@$tmphref) {
                        die "Merge key does not support merging non-hashmaps"
                            unless (ref $multi eq 'HASH');
                        my %tmphash = %$multi;
                        %$ref = (%tmphash, %$ref);
                        push @_, grep {ref eq 'HASH' or ref eq 'ARRAY'} values %$ref;
                    }
                    delete $ref->{'<<'};
                }
                else {
                    die "Merge key does not support merging non-hashmaps"
                        unless (ref $tmphref eq 'HASH');
                    my %tmphash = %$tmphref;
                    delete $ref->{'<<'};
                    %$ref = (%tmphash, %$ref);
                }
            }
            push @_, grep {ref eq 'HASH' or ref eq 'ARRAY'} values %$ref;
        }
        elsif ($type eq 'ARRAY')
        {
            push @_, grep {ref eq 'HASH' or ref eq 'ARRAY'} @$ref;
        }
    }
    return $orig;
}
1
