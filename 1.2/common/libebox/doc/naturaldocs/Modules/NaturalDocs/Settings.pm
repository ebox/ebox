###############################################################################
#
#   Package: NaturalDocs::Settings
#
###############################################################################
#
#   A package to handle the command line and various other program settings.
#
#   Usage and Dependencies:
#
#       - The <Constant Functions> can be called immediately.
#
#       - Prior to initialization, <NaturalDocs::Builder> must have all its output packages registered.
#
#       - To initialize, call <Load()>.  All functions except <InputDirectoryNameOf()> will then be available.
#
#       - <GenerateDirectoryNames()> must be called before <InputDirectoryNameOf()> will work.  Currently it is called by
#          <NaturalDocs::Menu->LoadAndUpdate()>.
#
###############################################################################

# This file is part of Natural Docs, which is Copyright � 2003-2004 Greg Valure
# Natural Docs is licensed under the GPL

use Cwd ();

use NaturalDocs::Settings::BuildTarget;

use strict;
use integer;

package NaturalDocs::Settings;



###############################################################################
# Group: Variables


# handle: SETTINGSFILEHANDLE
# The file handle used with <Settings.txt>.

# handle: PREVIOUS_SETTINGS_FILEHANDLE
# The file handle used with <PreviousSettings.nd>.

# array: inputDirectories
# An array of input directories.
my @inputDirectories;

# array: inputDirectoryNames
# An array of the input directory names.  Each name corresponds to the directory of the same index in <inputDirectories>.
my @inputDirectoryNames;

# array: excludedInputDirectories
# An array of input directories to exclude.
my @excludedInputDirectories;

# var: projectDirectory
# The project directory.
my $projectDirectory;

# array: buildTargets
# An array of <NaturalDocs::Settings::BuildTarget>s.
my @buildTargets;

# var: documentedOnly
# Whether undocumented code aspects should be included in the output.
my $documentedOnly;

# int: tabLength
# The number of spaces in tabs.
my $tabLength;

# bool: noAutoGroup
# Whether auto-grouping is turned off.
my $noAutoGroup;

# bool: rebuildData
# Whether the script should rebuild all data files from scratch.
my $rebuildData;

# bool: rebuildOutput
# Whether the script should rebuild all output files from scratch.
my $rebuildOutput;

# bool: isQuiet
# Whether the script should be run in quiet mode or not.
my $isQuiet;

# array: styles
# An array of style names to use, most important first.
my @styles;


###############################################################################
# Group: Files

#
#   File: Settings.txt
#
#   The file that stores the Natural Docs build targets.
#
#   Format:
#
#       The file is plain text.  Blank lines can appear anywhere and are ignored.  Tags and their content must be completely
#       contained on one line.
#
#       > # [comment]
#
#       The file supports single-line comments via #.  They can appear alone on a line or after content.
#
#       > Format: [version]
#       > TabLength: [length]
#       > Style: [style]
#
#       The file format version, tab length, and default style are specified as above.  Each can only be specified once, with
#       subsequent ones being ignored.  Notice that the tags correspond to the long forms of the command line options.
#
#       > Source: [directory]
#       > Input: [directory]
#
#       The input directory is specified as above.  As in the command line, either "Source" or "Input" can be used.
#
#       > [Extension Option]: [opton]
#
#       Options for extensions can be specified as well.  The long form is used as the tag.
#
#       > Option: [HeadersOnly], [Quiet], [Extension Option]
#
#       Options that don't have parameters can be specified in an Option line.  The commas are not required.
#
#       > Output: [name]
#
#       Specifies an output target with a user defined name.  The name is what will be referenced from the command line, and the
#       name "All" is reserved.
#
#       *The options below can only be specified after an output tag.*  Everything that follows an output tag is part of that target's
#       options until the next output tag.
#
#       > Format: [format]
#
#       The output format of the target.
#
#       > Directory: [directory]
#       > Location: [directory]
#       > Folder: [directory]
#
#       The output directory of the target.  All are synonyms.
#
#       > Style: [style]
#
#       The style of the output target.  This overrides the default and is optional.
#


#
#   File: PreviousSettings.nd
#
#   Stores the previous command line settings.
#
#   Format:
#
#       > [BINARY_FORMAT]
#       > [VersionInt: app version]
#
#       The file starts with the standard <BINARY_FORMAT> <VersionInt> header.
#
#       > [UInt8: tab length]
#       > [UInt8: documented only (0 or 1)]
#       > [UInt8: no auto-group (0 or 1)]
#       >
#       > [UInt8: number of input directories]
#       > [AString16: input directory] [AString16: input directory name] ...
#
#       A count of input directories, then that number of directory/name pairs.
#
#       > [UInt8: number of output targets]
#       > [AString16: output directory] [AString16: output format command line option] ...
#
#       A count of output targets, then that number of directory/format pairs.
#
#
#   Revisions:
#
#       1.3:
#
#           - Removed headers-only, which was a 0/1 UInt8 after tab length.
#           - Change auto-group level (1 = no, 2 = yes, 3 = full only) to no auto-group (0 or 1).
#
#       1.22:
#
#           - Added auto-group level.
#
#       1.2:
#
#           - File was added to the project.  Prior to 1.2, it didn't exist.
#


###############################################################################
# Group: Action Functions

#
#   Function: Load
#
#   Loads and parses all settings from the command line and configuration files.  Will exit if the options are invalid or the syntax
#   reference was requested.
#
sub Load
    {
    my ($self) = @_;

    $self->ParseCommandLine();
    $self->LoadAndComparePreviousSettings();
    };


#
#   Function: Save
#
#   Saves all settings in configuration files to disk.
#
sub Save
    {
    my ($self) = @_;

    $self->SavePreviousSettings();
    };


#
#   Function: GenerateDirectoryNames
#
#   Generates names for each of the input directories, which can later be retrieved with <InputDirectoryNameOf()>.
#
#   Parameters:
#
#       hints - A hashref of suggested names, where the keys are the directories and the values are the names.  These take
#                 precedence over anything generated.  Directories here that aren't on the list of input directories are ignored.
#                 This parameter may be undef.
#
sub GenerateDirectoryNames #(hints)
    {
    my ($self, $hints) = @_;

    my %usedNames;


    # Pass one applies all names from the hints.

    if (defined $hints)
        {
        for (my $i = 0; $i < scalar @inputDirectories; $i++)
            {
            if (exists $hints->{$inputDirectories[$i]})
                {
                $inputDirectoryNames[$i] = $hints->{$inputDirectories[$i]};
                $usedNames{ $hints->{$inputDirectories[$i]} } = 1;
                };
            };
        };


    # Pass two generates names for anything remaining.

    for (my $i = 0; $i < scalar @inputDirectories; $i++)
        {
        if (!defined $inputDirectoryNames[$i])
            {
            my $name;

            if (!exists $usedNames{'default'})
                {  $name = 'default';  }
            else
                {
                # The first attempt at a name is the last directory that isn't already used.

                my ($volume, $dirString, $file) = NaturalDocs::File->SplitPath($inputDirectories[$i], 1);
                my @directories = NaturalDocs::File->SplitDirectories($dirString);

                while (scalar @directories && !defined $name)
                    {
                    my $directory = pop @directories;
                    if (!exists $usedNames{$directory})
                        {  $name = $directory;  };
                    };

                if (!defined $name)
                    {
                    # If that didn't work, the second attempt is a number.

                    my $number = 1;
                    while (!exists $usedNames{$number})
                        {  $number++;  };

                    $name = $number;
                    };
                };

            $inputDirectoryNames[$i] = $name;
            $usedNames{$name} = 1;
            };
        };
    };


###############################################################################
# Group: Information Functions


# Function: InputDirectories
# Returns an arrayref of input directories.  Do not change.
sub InputDirectories
    {  return \@inputDirectories;  };

# Function: InputDirectoryNameOf
# Returns the generated name of the passed input directory.  <GenerateDirectoryNames()> must be called once before this
# function is available.  One possible directory name is "default", and it will always be used if there has never been more than
# one input directory.
sub InputDirectoryNameOf #(directory)
    {
    my ($self, $directory) = @_;

    my $name;

    for (my $i = 0; $i < scalar @inputDirectories && !defined $name; $i++)
        {
        if ($directory eq $inputDirectories[$i])
            {  $name = $inputDirectoryNames[$i];  };
        };

    return $name;
    };

# Function: SplitFromInputDirectory
# Takes an input file name and returns the array ( inputDirectory, relativePath ).
sub SplitFromInputDirectory #(file)
    {
    my ($self, $file) = @_;

    foreach my $directory (@inputDirectories)
        {
        if (NaturalDocs::File->IsSubPathOf($directory, $file))
            {  return ( $directory, NaturalDocs::File->MakeRelativePath($directory, $file) );  };
        };

    return ( );
    };

# Function: ExcludedInputDirectories
# Returns an arrayref of input directories to exclude.  Do not change.
sub ExcludedInputDirectories
    {  return \@excludedInputDirectories;  };

# Function: BuildTargets
# Returns an arrayref of <NaturalDocs::Settings::BuildTarget>s.  Do not change.
sub BuildTargets
    {  return \@buildTargets;  };

#
#   Function: OutputDirectoryOf
#
#   Returns the output directory of a builder object.
#
#   Parameters:
#
#       object - The builder object, whose class is derived from <NaturalDocs::Builder::Base>.
#
#   Returns:
#
#       The builder directory, or undef if the object wasn't found..
#
sub OutputDirectoryOf #(object)
    {
    my ($self, $object) = @_;

    foreach my $buildTarget (@buildTargets)
        {
        if ($buildTarget->Builder() == $object)
            {  return $buildTarget->Directory();  };
        };

    return undef;
    };


# Function: Styles
# Returns an arrayref of the styles associated with the output.
sub Styles
    {  return \@styles;  };

# Function: ProjectDirectory
# Returns the project directory.
sub ProjectDirectory
    {  return $projectDirectory;  };

# Function: ProjectDataDirectory
# Returns the project data directory.
sub ProjectDataDirectory
    {  return NaturalDocs::File->JoinPaths($projectDirectory, 'Data', 1);  };

# Function: StyleDirectory
# Returns the main style directory.
sub StyleDirectory
    {  return NaturalDocs::File->JoinPaths($FindBin::RealBin, 'Styles', 1);  };

# Function: JavaScriptDirectory
# Returns the main JavaScript directory.
sub JavaScriptDirectory
    {  return NaturalDocs::File->JoinPaths($FindBin::RealBin, 'JavaScript', 1);  };

# Function: ConfigDirectory
# Returns the main configuration directory.
sub ConfigDirectory
    {  return NaturalDocs::File->JoinPaths($FindBin::RealBin, 'Config', 1);  };

# Function: DocumentedOnly
# Returns whether undocumented code aspects should be included in the output.
sub DocumentedOnly
    {  return $documentedOnly;  };

# Function: TabLength
# Returns the number of spaces tabs should be expanded to.
sub TabLength
    {  return $tabLength;  };

# Function: NoAutoGroup
# Returns whether auto-grouping is turned off.
sub NoAutoGroup
    {  return $noAutoGroup;  };

# Function: RebuildData
# Returns whether the script should rebuild all data files from scratch.
sub RebuildData
    {  return $rebuildData;  };

# Function: RebuildOutput
# Returns whether the script should rebuild all output files from scratch.
sub RebuildOutput
    {  return $rebuildOutput;  };

# Function: IsQuiet
# Returns whether the script should be run in quiet mode or not.
sub IsQuiet
    {  return $isQuiet;  };


###############################################################################
# Group: Constant Functions

#
#   Function: AppVersion
#
#   Returns Natural Docs' version number as an integer.  Use <TextAppVersion()> to get a printable version.
#
sub AppVersion
    {
    my ($self) = @_;
    return NaturalDocs::Version->FromString($self->TextAppVersion());
    };

#
#   Function: TextAppVersion
#
#   Returns Natural Docs' version number as plain text.
#
sub TextAppVersion
    {  return '1.3';  };

#
#   Function: AppURL
#
#   Returns a string of the project's current web address.
#
sub AppURL
    {  return 'http://www.naturaldocs.org';  };



###############################################################################
# Group: Support Functions


#
#   Function: ParseCommandLine
#
#   Parses and validates the command line.  Will cause the script to exit if the options ask for the syntax reference or
#   are invalid.
#
sub ParseCommandLine
    {
    my ($self) = @_;

    my %synonyms = ( 'input'    => '-i',
                                  'source' => '-i',
                                  'excludeinput' => '-xi',
                                  'excludesource' => '-xi',
                                  'output'  => '-o',
                                  'project' => '-p',
                                  'documentedonly' => '-do',
                                  'style'    => '-s',
                                  'rebuild' => '-r',
                                  'rebuildoutput' => '-ro',
                                  'tablength' => '-t',
                                  'quiet'    => '-q',
                                  'headersonly' => '-ho',
                                  'help'     => '-h',
                                  'autogroup' => '-ag',
                                  'noautogroup' => '-nag' );


    my @errorMessages;

    my $valueRef;
    my $option;

    my @outputStrings;


    # Sometimes $valueRef is set to $ignored instead of undef because we don't want certain errors to cause other,
    # unnecessary errors.  For example, if they set the input directory twice, we want to show that error and swallow the
    # specified directory without complaint.  Otherwise it would complain about the directory too as if it were random crap
    # inserted into the command line.
    my $ignored;

    my $index = 0;

    while ($index < scalar @ARGV)
        {
        my $arg = $ARGV[$index];

        if (substr($arg, 0, 1) eq '-')
            {
            $option = lc($arg);

            # Support options like -t2 as well as -t 2.
            if ($option =~ /^([^0-9]+)([0-9]+)$/)
                {
                $option = $1;
                splice(@ARGV, $index + 1, 0, $2);
                };

            # Convert long forms to short.
            if (substr($option, 1, 1) eq '-')
                {
                # Strip all dashes.
                my $newOption = $option;
                $newOption =~ tr/-//d;

                if (exists $synonyms{$newOption})
                    {  $option = $synonyms{$newOption};  }
                }

            if ($option eq '-i')
                {
                push @inputDirectories, undef;
                $valueRef = \$inputDirectories[-1];
                }
            elsif ($option eq '-xi')
                {
                push @excludedInputDirectories, undef;
                $valueRef = \$excludedInputDirectories[-1];
                }
            elsif ($option eq '-p')
                {
                if (defined $projectDirectory)
                    {
                    push @errorMessages, 'You cannot have more than one project directory.';
                    $valueRef = \$ignored;
                    }
                else
                    {  $valueRef = \$projectDirectory;  };
                }
            elsif ($option eq '-o')
                {
                push @outputStrings, undef;
                $valueRef = \$outputStrings[-1];
                }
            elsif ($option eq '-s')
                {
                $valueRef = \$styles[0];
                }
            elsif ($option eq '-t')
                {
                $valueRef = \$tabLength;
                }
            elsif ($option eq '-ag')
                {
                push @errorMessages, 'The -ag setting is no longer supported.  You can use -nag (--no-auto-group) to turn off '
                                               . "auto-grouping, but there aren't multiple levels anymore.";
                $valueRef = \$ignored;
                }

            # Options that aren't followed by content.
            else
                {
                $valueRef = undef;

                if ($option eq '-r')
                    {
                    $rebuildData = 1;
                    $rebuildOutput = 1;
                    }
                elsif ($option eq '-ro')
                    {  $rebuildOutput = 1;  }
                elsif ($option eq '-do')
                    {  $documentedOnly = 1;  }
                elsif ($option eq '-q')
                    {  $isQuiet = 1;  }
                elsif ($option eq '-ho')
                    {
                    push @errorMessages, 'The -ho setting is no longer supported.  You can have Natural Docs skip over the source file '
                                                   . 'extensions by editing Languages.txt in your project directory.';
                    }
                elsif ($option eq '-nag')
                    {  $noAutoGroup = 1;  }
                elsif ($option eq '-?' || $option eq '-h')
                    {
                    $self->PrintSyntax();
                    exit;
                    }
                else
                    {  push @errorMessages, 'Unrecognized option ' . $option;  };

                };

            }

        # Is a segment of text, not an option...
        else
            {
            if (defined $valueRef)
                {
                # We want to preserve spaces in paths.
                if (defined $$valueRef)
                    {  $$valueRef .= ' ';  };

                $$valueRef .= $arg;
                }

            else
                {
                push @errorMessages, 'Unrecognized element ' . $arg;
                };
            };

        $index++;
        };


    # Validate the style, if specified.

    if ($styles[0])
        {
        my @stylePieces = split(/ +/, $styles[0]);
        @styles = ( );

        while (scalar @stylePieces)
            {
            if (lc($stylePieces[0]) eq 'custom')
                {
                push @errorMessages, 'The "Custom" style setting is no longer supported.  Copy your custom style sheet to your '
                                               . 'project directory and you can refer to it with -s.';
                shift @stylePieces;
                }
            else
                {
                # People may use styles with spaces in them.  If a style doesn't exist, we need to join the pieces until we find one that
                # does or we run out of pieces.

                my $extras = 0;
                my $success;

                while ($extras < scalar @stylePieces)
                    {
                    my $style;

                    if (!$extras)
                        {  $style = $stylePieces[0];  }
                    else
                        {  $style = join(' ', @stylePieces[0..$extras]);  };

                    my $cssFile = NaturalDocs::File->JoinPaths( $self->StyleDirectory(), $style . '.css' );
                    if (-e $cssFile)
                        {
                        push @styles, $style;
                        splice(@stylePieces, 0, 1 + $extras);
                        $success = 1;
                        last;
                        }
                    else
                        {
                        $cssFile = NaturalDocs::File->JoinPaths( $self->ProjectDirectory(), $style . '.css' );

                        if (-e $cssFile)
                            {
                            push @styles, $style;
                            splice(@stylePieces, 0, 1 + $extras);
                            $success = 1;
                            last;
                            }
                        else
                            {  $extras++;  };
                        };
                    };

                if (!$success)
                    {
                    push @errorMessages, 'The style "' . $stylePieces[0] . '" does not exist.';
                    shift @stylePieces;
                    };
                };
            };
        }
    else
        {  @styles = ( 'Default' );  };


    # Decode and validate the output strings.

    my %outputDirectories;

    foreach my $outputString (@outputStrings)
        {
        my ($format, $directory) = split(/ /, $outputString, 2);

        if (!defined $directory)
            {  push @errorMessages, 'The -o option needs two parameters: -o [format] [directory]';  }
        else
            {
            if (!NaturalDocs::File->PathIsAbsolute($directory))
                {  $directory = NaturalDocs::File->JoinPaths(Cwd::cwd(), $directory, 1);  };

            $directory = NaturalDocs::File->CanonizePath($directory);

            if (! -e $directory || ! -d $directory)
                {
                # They may have forgotten the format portion and the directory name had a space in it.
                if (-e ($format . ' ' . $directory) && -d ($format . ' ' . $directory))
                    {
                    push @errorMessages, 'The -o option needs two parameters: -o [format] [directory]';
                    $format = undef;
                    }
                else
                    {  push @errorMessages, 'The output directory ' . $directory . ' does not exist.';  }
                }
            elsif (exists $outputDirectories{$directory})
                {  push @errorMessages, 'You cannot specify the output directory ' . $directory . ' more than once.';  }
            else
                {  $outputDirectories{$directory} = 1;  };

            if (defined $format)
                {
                my $builderPackage = NaturalDocs::Builder->OutputPackageOf($format);

                if (defined $builderPackage)
                    {
                    push @buildTargets,
                            NaturalDocs::Settings::BuildTarget->New(undef, $builderPackage->New(), $directory);
                    }
                else
                    {
                    push @errorMessages, 'The output format ' . $format . ' doesn\'t exist or is not installed.';
                    $valueRef = \$ignored;
                    };
                };
            };
        };

    if (!scalar @buildTargets)
        {  push @errorMessages, 'You did not specify an output directory.';  };


    # Make sure the input and project directories are specified, canonized, and exist.

    if (scalar @inputDirectories)
        {
        for (my $i = 0; $i < scalar @inputDirectories; $i++)
            {
            if (!NaturalDocs::File->PathIsAbsolute($inputDirectories[$i]))
                {  $inputDirectories[$i] = NaturalDocs::File->JoinPaths(Cwd::cwd(), $inputDirectories[$i], 1);  };

            $inputDirectories[$i] = NaturalDocs::File->CanonizePath($inputDirectories[$i]);

            if (! -e $inputDirectories[$i] || ! -d $inputDirectories[$i])
                {  push @errorMessages, 'The input directory ' . $inputDirectories[$i] . ' does not exist.';  };
            };
        }
    else
        {  push @errorMessages, 'You did not specify an input (source) directory.';  };

    if (defined $projectDirectory)
        {
        if (!NaturalDocs::File->PathIsAbsolute($projectDirectory))
            {  $projectDirectory = NaturalDocs::File->JoinPaths(Cwd::cwd(), $projectDirectory, 1);  };

        $projectDirectory = NaturalDocs::File->CanonizePath($projectDirectory);

        if (! -e $projectDirectory || ! -d $projectDirectory)
            {  push @errorMessages, 'The project directory ' . $projectDirectory . ' does not exist.';  };

        # Create the Data subdirectory if it doesn't exist.
        NaturalDocs::File->CreatePath( NaturalDocs::File->JoinPaths($projectDirectory, 'Data', 1) );
        }
    else
        {  push @errorMessages, 'You did not specify a project directory.';  };


    # Make sure the excluded input directories are canonized, and add the project and output directories to the list.

    for (my $i = 0; $i < scalar @excludedInputDirectories; $i++)
        {
        if (!NaturalDocs::File->PathIsAbsolute($excludedInputDirectories[$i]))
            {  $excludedInputDirectories[$i] = NaturalDocs::File->JoinPaths(Cwd::cwd(), $excludedInputDirectories[$i], 1);  };

        $excludedInputDirectories[$i] = NaturalDocs::File->CanonizePath($excludedInputDirectories[$i]);
        };

    push @excludedInputDirectories, $projectDirectory;

    foreach my $buildTarget (@buildTargets)
        {
        push @excludedInputDirectories, $buildTarget->Directory();
        };


    # Determine the tab length, and default to four if not specified.

    if (defined $tabLength)
        {
        if ($tabLength !~ /^[0-9]+$/)
            {  push @errorMessages, 'The tab length must be a number.';  };
        }
    else
        {  $tabLength = 4;  };


    # Exit with the error message if there was one.

    if (scalar @errorMessages)
        {
        print join("\n", @errorMessages) . "\nType NaturalDocs -h to see the syntax reference.\n";
        exit;
        };
    };

#
#   Function: PrintSyntax
#
#   Prints the syntax reference.
#
sub PrintSyntax
    {
    my ($self) = @_;

    # Make sure all line lengths are under 80 characters.

    print

    "Natural Docs, version " . $self->TextAppVersion() . "\n"
    . $self->AppURL() . "\n"
    . "This program is licensed under the GPL\n"
    . "--------------------------------------\n"
    . "\n"
    . "Syntax:\n"
    . "\n"
    . "    NaturalDocs -i [input (source) directory]\n"
    . "               (-i [input (source) directory] ...)\n"
    . "                -o [output format] [output directory]\n"
    . "               (-o [output format] [output directory] ...)\n"
    . "                -p [project directory]\n"
    . "                [options]\n"
    . "\n"
    . "Examples:\n"
    . "\n"
    . "    NaturalDocs -i C:\\My Project\\Source -o HTML C:\\My Project\\Docs\n"
    . "                -p C:\\My Project\\Natural Docs\n"
    . "    NaturalDocs -i /src/project -o HTML /doc/project\n"
    . "                -p /etc/naturaldocs/project -s Small -q\n"
    . "\n"
    . "Required Parameters:\n"
    . "\n"
    . " -i [dir]\n--input [dir]\n--source [dir]\n"
    . "     Specifies the input (source) directory.  Required.\n"
    . "     Can be specified multiple times.\n"
    . "\n"
    . " -o [fmt] [dir]\n--output [fmt] [dir]\n"
    . "    Specifies the output format and directory.  Required.\n"
    . "    Can be specified multiple times, but only once per directory.\n"
    . "    Possible output formats:\n";

    $self->PrintOutputFormats('    - ');

    print
    "\n"
    . " -p [dir]\n--project [dir]\n"
    . "    Specifies the project directory.  Required.\n"
    . "    There needs to be a unique project directory for every source directory.\n"
    . "\n"
    . "Optional Parameters:\n"
    . "\n"
    . " -s [style] ([style] [style] ...)\n--style [style] ([style] [style] ...)\n"
    . "    Specifies the CSS style when building HTML output.  If multiple styles are\n"
    . "    specified, they will all be included in the order given.\n"
    . "\n"
    . " -do\n--documented-only\n"
    . "    Specifies only documented code aspects should be included in the output.\n"
    . "\n"
    . " -t [len]\n--tab-length [len]\n"
    . "    Specifies the number of spaces tabs should be expanded to.  This only needs\n"
    . "    to be set if you use tabs in example code and text diagrams.  Defaults to 4.\n"
    . "\n"
    . " -xi [dir]\n--exclude-input [dir]\n--exclude-source [dir]\n"
    . "     Excludes an input (source) directory from the documentation.\n"
    . "     Automatically done for the project and output directories.  Can\n"
    . "     be specified multiple times.\n"
    . "\n"
    . " -nag\n--no-auto-group\n"
    . "    Turns off auto-grouping completely.\n"
    . "\n"
    . " -r\n--rebuild\n"
    . "    Rebuilds all output and data files from scratch.\n"
    . "    Does not affect the menu file.\n"
    . "\n"
    . " -ro\n--rebuild-output\n"
    . "    Rebuilds all output files from scratch.\n"
    . "\n"
    . " -q\n--quiet\n"
    . "    Suppresses all non-error output.\n"
    . "\n"
    . " -?\n -h\n--help\n"
    . "    Displays this syntax reference.\n";
    };


#
#   Function: PrintOutputFormats
#
#   Prints all the possible output formats that can be specified with -o.  Each one will be placed on its own line.
#
#   Parameters:
#
#       prefix - Characters to prefix each one with, such as for indentation.
#
sub PrintOutputFormats #(prefix)
    {
    my ($self, $prefix) = @_;

    my $outputPackages = NaturalDocs::Builder::OutputPackages();

    foreach my $outputPackage (@$outputPackages)
        {
        print $prefix . $outputPackage->CommandLineOption() . "\n";
        };
    };


#
#   Function: LoadAndComparePreviousSettings
#
#   Loads <PreviousSettings.nd> and compares the values there with those in the command line.  If differences require it,
#   sets <rebuildData> and/or <rebuildOutput>.
#
sub LoadAndComparePreviousSettings
    {
    my ($self) = @_;

    my $fileIsOkay = 1;
    my $fileName = NaturalDocs::Project->PreviousSettingsFile();
    my $version;

    if (!open(PREVIOUS_SETTINGS_FILEHANDLE, '<' . $fileName))
        {  $fileIsOkay = undef;  }
    else
        {
        # See if it's binary.
        binmode(PREVIOUS_SETTINGS_FILEHANDLE);

        my $firstChar;
        read(PREVIOUS_SETTINGS_FILEHANDLE, $firstChar, 1);

        if ($firstChar != ::BINARY_FORMAT())
            {
            close(PREVIOUS_SETTINGS_FILEHANDLE);
            $fileIsOkay = undef;
            }
        else
            {
            $version = NaturalDocs::Version->FromBinaryFile(\*PREVIOUS_SETTINGS_FILEHANDLE);

            # The file format changed in 1.3.

            if ($version > NaturalDocs::Settings->AppVersion() || $version < NaturalDocs::Version->FromString('1.3'))
                {
                close(PREVIOUS_SETTINGS_FILEHANDLE);
                $fileIsOkay = undef;
                };
            };
        };


    if (!$fileIsOkay)
        {
        # Rebuild everything.
        $rebuildData = 1;
        $rebuildOutput = 1;
        }
    else
        {
        my $raw;

        # [UInt8: tab expansion]
        # [UInt8: documented only (0 or 1)]
        # [UInt8: no auto-group (0 or 1)]
        # [UInt8: number of input directories]

        read(PREVIOUS_SETTINGS_FILEHANDLE, $raw, 4);
        my ($prevTabLength, $prevDocumentedOnly, $prevNoAutoGroup, $inputDirectoryCount)
            = unpack('CCCC', $raw);

        if ($prevTabLength != $self->TabLength())
            {
            # We need to rebuild all output because this affects all text diagrams.
            $rebuildOutput = 1;
            };

        if ($prevDocumentedOnly == 0)
            {  $prevDocumentedOnly = undef;  };
        if ($prevNoAutoGroup == 0)
            {  $prevNoAutoGroup = undef;  };

        if ($prevDocumentedOnly != $self->DocumentedOnly() ||
            $prevNoAutoGroup != $self->NoAutoGroup())
            {
            # These are biggies, since they affects the symbol table as well.  Nuke everything.
            $rebuildData = 1;
            $rebuildOutput = 1;
            };


        while ($inputDirectoryCount)
            {
            # [AString16: input directory] [AString16: input directory name] ...

            read(PREVIOUS_SETTINGS_FILEHANDLE, $raw, 2);
            my $inputDirectoryLength = unpack('n', $raw);

            my $inputDirectory;
            read(PREVIOUS_SETTINGS_FILEHANDLE, $inputDirectory, $inputDirectoryLength);

            read (PREVIOUS_SETTINGS_FILEHANDLE, $raw, 2);
            my $inputDirectoryNameLength = unpack('n', $raw);

            my $inputDirectoryName;
            read(PREVIOUS_SETTINGS_FILEHANDLE, $inputDirectoryName, $inputDirectoryNameLength);

            # Not doing anything with this for now.

            $inputDirectoryCount--;
            };


        # [UInt8: number of output targets]

        read(PREVIOUS_SETTINGS_FILEHANDLE, $raw, 1);
        my $outputTargetCount = unpack('C', $raw);

        # Keys are the directories, values are the command line options.
        my %previousOutputDirectories;

        while ($outputTargetCount)
            {
            # [AString16: output directory] [AString16: output format command line option] ...

            read(PREVIOUS_SETTINGS_FILEHANDLE, $raw, 2);
            my $outputDirectoryLength = unpack('n', $raw);

            my $outputDirectory;
            read(PREVIOUS_SETTINGS_FILEHANDLE, $outputDirectory, $outputDirectoryLength);

            read (PREVIOUS_SETTINGS_FILEHANDLE, $raw, 2);
            my $outputCommandLength = unpack('n', $raw);

            my $outputCommand;
            read(PREVIOUS_SETTINGS_FILEHANDLE, $outputCommand, $outputCommandLength);

            $previousOutputDirectories{$outputDirectory} = $outputCommand;

            $outputTargetCount--;
            };

        # Check if any targets were added to the command line, or if their formats changed.  We don't care if targets were
        # removed.
        my $buildTargets = $self->BuildTargets();

        foreach my $buildTarget (@$buildTargets)
            {
            if (!exists $previousOutputDirectories{$buildTarget->Directory()} ||
                $buildTarget->Builder()->CommandLineOption() ne $previousOutputDirectories{$buildTarget->Directory()})
                {
                $rebuildOutput = 1;
                last;
                };
            };

        close(PREVIOUSSTATEFILEHANDLE);
        };
    };


#
#   Function: SavePreviousSettings
#
#   Saves the settings into <PreviousSettings.nd>.
#
sub SavePreviousSettings
    {
    my ($self) = @_;

    open (PREVIOUS_SETTINGS_FILEHANDLE, '>' . NaturalDocs::Project->PreviousSettingsFile())
        or die "Couldn't save " . NaturalDocs::Project->PreviousSettingsFile() . ".\n";

    binmode(PREVIOUS_SETTINGS_FILEHANDLE);

    print PREVIOUS_SETTINGS_FILEHANDLE '' . ::BINARY_FORMAT();
    NaturalDocs::Version->ToBinaryFile(\*PREVIOUS_SETTINGS_FILEHANDLE, NaturalDocs::Settings->AppVersion());

    # [UInt8: tab length]
    # [UInt8: documented only (0 or 1)]
    # [UInt8: no auto-group (0 or 1)]
    # [UInt8: number of input directories]

    my $inputDirectories = $self->InputDirectories();

    print PREVIOUS_SETTINGS_FILEHANDLE pack('CCCC', $self->TabLength(), ($self->DocumentedOnly() ? 1 : 0),
                                                                                    ($self->NoAutoGroup() ? 1 : 0), scalar @$inputDirectories);

    foreach my $inputDirectory (@$inputDirectories)
        {
        my $inputDirectoryName = $self->InputDirectoryNameOf($inputDirectory);

        # [AString16: input directory] [AString16: input directory name] ...
        print PREVIOUS_SETTINGS_FILEHANDLE pack('nA*nA*', length($inputDirectory), $inputDirectory,
                                                                                          length($inputDirectoryName), $inputDirectoryName);
        };

    # [UInt8: number of output targets]

    my $buildTargets = $self->BuildTargets();
    print PREVIOUS_SETTINGS_FILEHANDLE pack('C', scalar @$buildTargets);

    foreach my $buildTarget (@$buildTargets)
        {
        my $buildTargetDirectory = $buildTarget->Directory();
        my $buildTargetCommand = $buildTarget->Builder()->CommandLineOption();

        # [AString16: output directory] [AString16: output format command line option] ...
        print PREVIOUS_SETTINGS_FILEHANDLE pack('nA*nA*', length($buildTargetDirectory), $buildTargetDirectory,
                                                                                          length($buildTargetCommand), $buildTargetCommand);
        };

    close(PREVIOUS_SETTINGS_FILEHANDLE);
    };


1;
