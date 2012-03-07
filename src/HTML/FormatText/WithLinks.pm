package HTML::FormatText::WithLinks;

use strict;
use URI::WithBase;
use HTML::TreeBuilder;
use base qw(HTML::FormatText);
use vars qw($VERSION);

$VERSION = '0.06';

sub new {

    my $proto = shift;
    my $class = ref( $proto ) || $proto;
    my $self  = $class->SUPER::new( @_ );
    $self->configure() unless @_;

    bless ( $self, $class );
    return $self;

}

sub configure {

    my ($self, $hash) = @_;

    # a base uri so we can resolve relative uris
    $self->{base} = $hash->{base};
    delete $hash->{base};
    $self->{base} =~ s#(.*?)/[^/]*$#$1/# if $self->{base};

    $self->{before_link} = '[%n]';
    $self->{after_link} = '';
    $self->{footnote} = '%n. %l';
    $self->{link_num_generator} = sub { return shift() + 1 };

    foreach ( qw( before_link after_link footnote link_num_generator 
                  with_emphasis ) ) {
        $self->{ $_ } = $hash->{ $_ } if exists $hash->{ $_ };
        delete $hash->{ $_ };
    }

    $self->SUPER::configure($hash);

}

# we need to do this as if you pass an HTML fragment without any
# containing block level markup (e.g. a p tag) then no indentation
# takes place so if we've not got a cur_pos we indent.
sub textflow {
    my $self = shift;
    $self->goto_lm unless defined $self->{cur_pos}; 
    $self->SUPER::textflow(@_);
}

sub a_start {

    my $self = shift;
    my $node = shift;
    # local urls are no use so we have to make them absolute
    my $href = $node->attr('href') || '';
    if ( $href ) {
        if ($href =~ m#^http:|^mailto:#) {
            push @{$self->{_links}}, $href;
        } else {
            my $u = URI::WithBase->new($href, $self->{base});
            push @{$self->{_links}}, $u->abs();
        }
        $self->out( $self->text('before_link') );
    }
    $self->SUPER::a_start();

}

sub a_end {

    my $self = shift;
    my $node = shift;
    my $text = $self->text('after_link');
# If we're just dealing with a fragment of HTML, with a link at the
# end, we get a space before the first footnote link if we do 
# $self->out( '' )
    if ($text ne '') {
        $self->out( $text );
    }
    $self->SUPER::a_end();

}

sub b_start {
    my $self = shift;
    $self->out( '_' ) if $self->{ with_emphasis };
    $self->SUPER::b_start();
}

sub b_end {
    my $self = shift;
    $self->out( '_' ) if $self->{ with_emphasis };
    $self->SUPER::b_end();
}

sub i_start {
    my $self = shift;
    $self->out( '/' ) if $self->{ with_emphasis };
    $self->SUPER::i_start();
}

sub i_end {
    my $self = shift;
    $self->out( '/' ) if $self->{ with_emphasis };
    $self->SUPER::i_end();
}

# print out our links
sub html_end {

    my $self = shift;
    if ( $self->{_links} and $self->{footnote} ) {
        $self->nl; $self->nl; # be tidy
        $self->goto_lm;
        for (0 .. $#{$self->{_links}}) {
            $self->goto_lm;
            $self->out(
                $self->text( 'footnote', $_, $self->{_links}->[$_] )
            );
            $self->nl;
        }
    }
    $self->SUPER::end();

}

sub _link_num {

    my ($self, $num) = @_;
    $num = $#{$self->{_links}} unless (defined $num);
    return &{$self->{link_num_generator}}($num);

}

sub text {

    my ($self, $type, $num, $href) = @_;
    $href = $self->{_links}->[$#{$self->{_links}}]
            unless (defined $num and defined $href);
    $num = $self->_link_num($num);
    my $text = $self->{$type};
    $text =~ s/%n/$num/g;
    $text =~ s/%l/$href/g;
    return $text;
}

sub parse {

    my $self = shift;
    my $text = shift;

    return undef unless defined $text;
    return '' if $text eq '';

    my $tree = HTML::TreeBuilder->new->parse( $text );

    return $self->_parse( $tree );
}

sub parse_file {

    my $self = shift;
    my $file = shift;

    unless (-e $file and -f $file) {
        $self->error("$file not found or not a regular file");
        return undef;
    }

    my $tree = HTML::TreeBuilder->new->parse_file( $file );
    
    return $self->_parse( $tree );
}

sub _parse {

    my $self = shift;
    my $tree = shift;

    unless ( $tree ) {
        $self->error( "HTML::TreeBuilder problem" . ( $! ? ": $!" : '' ) );
        return undef;
    }
    $tree->eof();

    my $return_text = $self->format( $tree );

    $tree->delete;

    return $return_text;
}
    

sub error {
    my $self = shift;
    if (@_) {
        $self->{error} = shift;
    }
    return $self->{error};
}

1;

__END__

=head1 NAME 

HTML::FormatText::WithLinks - HTML to text conversion with links as footnotes

=head1 SYNOPSIS

    use HTML::FormatText::WithLinks;

    my $f = HTML::FormatText::WithLinks->new();

    my $html = qq(
    <html>
    <body>
    <p>
        Some html with a <a href="http://example.com/">link</a>
    </p>
    </body>
    </html>
    );

    my $text = $f->parse($html);

    print $text;

    # results in something like

    Some html with a [1]link

    1. http://example.com/

    my $f2 = HTML::FormatText::WithLinks->new(
        before_link => '',
        after_link => ' [%l]',
        footnote => ''
    );

    $text = $f2->parse($html);
    print $text;

    # results in something like

    Some html with a link [http://example.com/]

    my $f3 = HTML::FormatText::WithLinks->new(
        link_num_generator => sub {
            return "*" x (shift() + 1);
        },
        footnote => '[%n] %l'
    );

    $text = $f3->parse($html);
    print $text;

    # results in something like

    Some html with a [*]link

    [*] http://example.com/

=head1 DESCRIPTION

HTML::FormatText::WithLinks takes HTML and turns it into plain text
but prints all the links in the HTML as footnotes. By default, it attempts
to mimic the format of the lynx text based web browser's --dump option.

=head1 METHODS

=head2 new

    my $f = HTML::FormatText::WithLinks->new( %options );

Returns a new instance. It accepts all the options of HTML::FormatText plus

=over

=item base

a base option. This should be set to a URI which will be used to turn any 
relative URIs on the HTML to absolute ones.

=item before_link (default: '[%n]')

=item after_link (default: '')

=item footnote (default: '[%n] %l')

a string to print before a link (i.e. when the <a> is found), 
after link has ended (i.e. when then </a> is found) and when printing 
out footnotes.

"%n" will be replaced by the link number, "%l" will be replaced by the 
link itself.

If footnote is set to '', no footnotes will be printed.

=item link_num_generator (default: sub { return shift() + 1 })

link_num_generator is a sub that returns the value to be printed for a 
given link number. The internal store starts numbering at 0.

=item with_emphasis

If set to 1 then italicised text will be surrounded by / and bolded text by _.

=back

=head2 parse

    my $text = $f->parse($html);

Takes some HTML and returns it as text. Returns undef on error.

Will also return undef if you don't pass it undef. Returns an empty 
string if passed an empty string.

=head2 parse_file

    my $text = $f->parse_file($filename);

Takes a filename and returns the contents of the file as plain text.
Returns undef on error.

=head2 error

    $f->error();

Returns the last error that occured. In practice this is likely to be 
either a warning that parse_file couldn't find the file or that
HTML::TreeBuilder failed.

=head1 CAVEATS

When passing HTML fragments the results may be a little unpredictable. 
I've tried to work round the most egregious of the issues but any 
unexpected results are welcome. 

Also note that if for some reason there is an a tag in the document
that does not have an href attribute then it will be quietly ignored.
If this is really a problem for anyone then let me know and I'll see
if I can think of a sensible thing to do in this case.

=head1 AUTHOR

Struan Donald. E<lt>struan@cpan.orgE<gt>

L<http://www.exo.org.uk/code/>

Ian Malpass E<lt>ian@indecorous.comE<gt> was responsible for the custom 
formatting bits and the nudge to release the code.

=head1 COPYRIGHT

Copyright (C) 2003 Struan Donald and Ian Malpass. All rights reserved.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1), HTML::Formatter.

=cut
