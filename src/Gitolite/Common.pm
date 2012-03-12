package Gitolite::Common;

# common (non-gitolite-specific) functions
# ----------------------------------------------------------------------

#<<<
@EXPORT = qw(
  print2  dbg     _mkdir  _open   ln_sf     tsh_rc      sort_u
  say     _warn   _chdir  _print            tsh_text    list_phy_repos
  say2    _die    _system slurp             tsh_lines
          trace           cleanup_conf_line tsh_try
          usage                             tsh_run
);
#>>>
use Exporter 'import';
use File::Path qw(mkpath);
use Carp qw(carp cluck croak confess);

use strict;
use warnings;

# ----------------------------------------------------------------------

sub print2 {
    local $/ = "\n";
    print STDERR @_;
}

sub say {
    local $/ = "\n";
    print @_, "\n";
}

sub say2 {
    local $/ = "\n";
    print STDERR @_, "\n";
}

sub trace {
    return unless defined( $ENV{D} );

    my $level = shift; return if $ENV{D} < $level;
    my $args  = ''; $args = join( ", ", @_ ) if @_;
    my $sub   = ( caller 1 )[3] || ''; $sub =~ s/.*://; $sub .= ' ' x ( 32 - length($sub) );
    say2 "TRACE $level $sub", (@_ ? shift : ());
    say2("TRACE $level " . (" " x 32), $_)for @_;
}

sub dbg {
    use Data::Dumper;
    return unless defined( $ENV{D} );
    for my $i (@_) {
        print STDERR "DBG: " . Dumper($i);
    }
}

sub _warn {
    if ( $ENV{D} and $ENV{D} >= 3 ) {
        cluck "WARNING: ", @_, "\n";
    } elsif ( defined( $ENV{D} ) ) {
        carp "WARNING: ", @_, "\n";
    } else {
        warn "WARNING: ", @_, "\n";
    }
}

sub _die {
    if ( $ENV{D} and $ENV{D} >= 3 ) {
        confess "FATAL: " . join( ",", @_ ) . "\n" if defined( $ENV{D} );
    } elsif ( defined( $ENV{D} ) ) {
        croak "FATAL: " . join( ",", @_ ) . "\n";
    } else {
        die "FATAL: " . join( ",", @_ ) . "\n";
    }
}

sub usage {
    _warn(shift) if @_;
    my $scriptname = ( caller() )[1];
    my $script     = slurp($scriptname);
    $script =~ /^=for usage(.*?)^=cut/sm;
    say2( $1 ? $1 : "...no usage message in $scriptname" );
    exit 1;
}

sub _mkdir {
    # it's not an error if the directory exists, but it is an error if it
    # doesn't exist and we can't create it
    my $dir  = shift;
    my $perm = shift;    # optional
    return if -d $dir;
    mkpath($dir);
    chmod $perm, $dir if $perm;
    return 1;
}

sub _chdir {
    chdir( $_[0] || $ENV{HOME} ) or _die "chdir $_[0] failed: $!\n";
}

sub _system {
    if ( system(@_) != 0 ) {
        say2 "system @_ failed";
        if ( $? == -1 ) {
            die "failed to execute: $!\n";
        } elsif ( $? & 127 ) {
            die "child died with signal " . ( $? & 127 ) . "\n";
        } else {
            die "child exited with value " . ( $? >> 8 ) . "\n";
        }
    }
}

sub _open {
    open( my $fh, $_[0], $_[1] ) or _die "open $_[1] failed: $!\n";
    return $fh;
}

sub _print {
    my ( $file, @text ) = @_;
    my $fh = _open( ">", "$file.$$" );
    print $fh @text;
    close($fh) or _die "close $file failed: $! at ", (caller)[1], " line ", (caller)[2], "\n";
    my $oldmode = ( ( stat $file )[2] );
    rename "$file.$$", $file;
    chmod $oldmode, $file if $oldmode;
}

sub slurp {
    return unless defined wantarray;
    local $/ = undef unless wantarray;
    my $fh = _open( "<", $_[0] );
    return <$fh>;
}

sub dos2unix {
    # WARNING: when calling this, make sure you supply a list context
    s/\r\n/\n/g for @_;
    return @_;
}

sub ln_sf {
    trace( 4, @_ );
    my ( $srcdir, $glob, $dstdir ) = @_;
    for my $hook ( glob("$srcdir/$glob") ) {
        $hook =~ s/$srcdir\///;
        unlink "$dstdir/$hook";
        symlink "$srcdir/$hook", "$dstdir/$hook" or croak "could not symlink $srcdir/$hook to $dstdir\n";
    }
}

sub sort_u {
    my %uniq;
    my $listref = shift;
    return [] unless @{ $listref };
    undef @uniq{ @{ $listref } }; # expect a listref
    my @sort_u = sort keys %uniq;
    return \@sort_u;
}

sub cleanup_conf_line {
    my $line = shift;

    # kill comments, but take care of "#" inside *simple* strings
    $line =~ s/^((".*?"|[^#"])*)#.*/$1/;
    # normalise whitespace; keeps later regexes very simple
    $line =~ s/=/ = /;
    $line =~ s/\s+/ /g;
    $line =~ s/^ //;
    $line =~ s/ $//;
    return $line;
}

{
    my @phy_repos = ();

    sub list_phy_repos {
        _die "'gitolite list_phy_repos' takes no arguments" if @ARGV;
        trace(3);

        # use cached value only if it exists *and* no arg was received (i.e.,
        # receiving *any* arg invalidates cache)
        return \@phy_repos if ( @phy_repos and not @_ );

        for my $repo (`find . -name "*.git" -prune`) {
            chomp($repo);
            $repo =~ s(\./(.*)\.git$)($1);
            push @phy_repos, $repo;
        }
        return sort_u(\@phy_repos);
    }
}

# ----------------------------------------------------------------------

# bare-minimum subset of 'Tsh' (see github.com/sitaramc/tsh)
{
    my ( $rc, $text );
    sub tsh_rc   { return $rc   || 0; }
    sub tsh_text { return $text || ''; }
    sub tsh_lines { return split /\n/, $text; }

    sub tsh_try {
        my $cmd = shift; die "try: expects only one argument" if @_;
        $text = `( $cmd ) 2>&1; echo -n RC=\$?`;
        if ( $text =~ s/RC=(\d+)$// ) {
            $rc = $1;
            trace( 4, $text );
            return ( not $rc );
        }
        die "couldnt find RC= in result; this should not happen:\n$text\n\n...\n";
    }

    sub tsh_run {
        open( my $fh, "-|", @_ ) or die "popen failed: $!";
        local $/ = undef; $text = <$fh>;
        close $fh; warn "pclose failed: $!" if $!;
        $rc = ( $? >> 8 );
        trace( 4, $text );
        return $text;
    }
}

1;