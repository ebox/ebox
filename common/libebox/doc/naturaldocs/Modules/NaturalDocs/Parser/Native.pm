###############################################################################
#
#   Package: NaturalDocs::Parser::Native
#
###############################################################################
#
#   A package that converts comments from Natural Docs' native format into <NaturalDocs::Parser::ParsedTopic> objects.
#   Unlike most second-level packages, these are packages and not object classes.
#
###############################################################################

# This file is part of Natural Docs, which is Copyright � 2003-2004 Greg Valure
# Natural Docs is licensed under the GPL


use strict;
use integer;

package NaturalDocs::Parser::Native;


###############################################################################
# Group: Variables


# Return values of TagType().  Not documented here.
use constant POSSIBLE_OPENING_TAG => 1;
use constant POSSIBLE_CLOSING_TAG => 2;
use constant NOT_A_TAG => 3;


#
#   var: package
#
#   A <SymbolString> representing the package normal topics will be a part of at the current point in the file.  This is a package variable
#   because it needs to be reserved between function calls.
#
my $package;

#
#   hash: functionListIgnoredHeadings
#
#   An existence hash of all the headings that prevent the parser from creating function list symbols.  Whenever one of
#   these headings are used in a function list topic, symbols are not created from definition lists until the next heading.  The keys
#   are in all lowercase.
#
my %functionListIgnoredHeadings = ( 'parameters' => 1,
                                                       'parameter' => 1,
                                                       'params' => 1,
                                                       'param' => 1,
                                                       'arguments' => 1,
                                                       'argument' => 1,
                                                       'args' => 1,
                                                       'arg' => 1 );


###############################################################################
# Group: Interface Functions


#
#   Function: Start
#
#   This will be called whenever a file is about to be parsed.  It allows the package to reset its internal state.
#
sub Start
    {
    my ($self) = @_;
    $package = undef;
    };


#
#   Function: ParseComment
#
#   This will be called whenever a comment capable of containing Natural Docs content is found.
#
#   Parameters:
#
#       commentLines - An arrayref of the comment's lines.  All tabs must be expanded into spaces, and all comment symbols,
#                               boxes, lines, and trailing whitespace should be removed.  Leading whitespace and multiple blank lines
#                               should be preserved.
#       lineNumber - The line number of the first of the comment lines.
#       parsedTopics - A reference to the array where any new <NaturalDocs::Parser::ParsedTopics> should be placed.
#
#   Returns:
#
#       The number of parsed topics added to the array, or zero if none.
#
sub ParseComment #(commentLines, lineNumber, parsedTopics)
    {
    my ($self, $commentLines, $lineNumber, $parsedTopics) = @_;

    my $topicCount = 0;
    my $prevLineBlank = 1;
    my $inCodeSection;

    my $type;
    my $typeInfo;
    my $isPlural;
    my $title;
    my $symbol;
    #my $package;  # package variable.

    my $index = 0;

    my $bodyStart = 0;
    my $bodyEnd = 0;  # Not inclusive.

    while ($index < scalar @$commentLines)
        {
        # Everything but leading whitespace was removed beforehand.

        # If we're in a code section...
        if ($inCodeSection)
            {
            if ($commentLines->[$index] =~ /^ *\( *(?:end|finish|done)(?: +(?:table|code|example|diagram))? *\)$/i)
                {  $inCodeSection = undef;  };

            $prevLineBlank = 0;
            $bodyEnd++;
            }

        # If the line is empty...
        elsif (!length($commentLines->[$index]))
            {
            $prevLineBlank = 1;
            $bodyEnd++;
            }

        # If the line has a recognized header and the previous line is blank...
        elsif ($prevLineBlank &&
                $commentLines->[$index] =~ /^ *([a-z0-9 ]*[a-z0-9]): +(.*)$/i &&
                (my ($newType, $newTypeInfo, $newIsPlural) = NaturalDocs::Topics->KeywordInfo($1)) )
            {
            my $newTitle = $2;

            # Process the previous one, if any.

            if (defined $type)
                {
                if ($typeInfo->Scope() == ::SCOPE_START() || $typeInfo->Scope() == ::SCOPE_END())
                    {  $package = undef;  };

                my $body = $self->FormatBody($commentLines, $bodyStart, $bodyEnd, $type, $isPlural);
                my $newTopic = $self->MakeParsedTopic($type, $title, $package, $body, $lineNumber + $bodyStart - 1, $isPlural);
                push @$parsedTopics, $newTopic;
                $topicCount++;

                $package = $newTopic->Package();
                };

            ($type, $typeInfo, $isPlural, $title) = ($newType, $newTypeInfo, $newIsPlural, $newTitle);

            $bodyStart = $index + 1;
            $bodyEnd = $index + 1;

            $prevLineBlank = 0;
            }

        # Line without recognized header
        else
            {
            $prevLineBlank = 0;
            $bodyEnd++;

            if ($commentLines->[$index] =~ /^ *\( *(?:(?:start|begin)? +)?(?:table|code|example|diagram) *\)$/i)
                {  $inCodeSection = 1;  };
            };


        $index++;
        };


    # Last one, if any.  This is the only one that gets the prototypes.
    if (defined $type)
        {
        if ($typeInfo->Scope() == ::SCOPE_START() || $typeInfo->Scope() == ::SCOPE_END())
            {  $package = undef;  };

        my $body = $self->FormatBody($commentLines, $bodyStart, $bodyEnd, $type, $isPlural);
        my $newTopic = $self->MakeParsedTopic($type, $title, $package, $body, $lineNumber + $bodyStart - 1, $isPlural);
        push @$parsedTopics, $newTopic;
        $topicCount++;

        $package = $newTopic->Package();
        };

    return $topicCount;
    };



###############################################################################
# Group: Support Functions


#
#   Function: MakeParsedTopic
#
#   Creates a <NaturalDocs::Parser::ParsedTopic> object for the passed parameters.  Scope is gotten from
#   the package variable <scope> instead of from the parameters.  The summary is generated from the body.
#
#   Parameters:
#
#       type         - The <TopicType>.
#       title          - The title of the topic.
#       package    - The package <SymbolString> the topic appears in.
#       body        - The topic's body in <NDMarkup>.
#       lineNumber - The topic's line number.
#       isList         - Whether the topic is a list.
#
#   Returns:
#
#       The <NaturalDocs::Parser::ParsedTopic> object.
#
sub MakeParsedTopic #(type, title, package, body, lineNumber, isList)
    {
    my ($self, $type, $title, $package, $body, $lineNumber, $isList) = @_;

    my $summary;

    if (defined $body)
        {  $summary = NaturalDocs::Parser->GetSummaryFromBody($body);  };

    return NaturalDocs::Parser::ParsedTopic->New($type, $title, $package, undef, undef, $summary,
                                                                         $body, $lineNumber, $isList);
    };


#
#    Function: FormatBody
#
#    Converts the section body to <NDMarkup>.
#
#    Parameters:
#
#       commentLines - The arrayref of comment lines.
#       startingIndex  - The starting index of the body to format.
#       endingIndex   - The ending index of the body to format, *not* inclusive.
#       type               - The type of the section.
#       isList              - Whether it's a list topic.
#
#    Returns:
#
#        The body formatted in <NDMarkup>.
#
sub FormatBody #(commentLines, startingIndex, endingIndex, type, isList)
    {
    my ($self, $commentLines, $startingIndex, $endingIndex, $type, $isList) = @_;

    use constant TAG_NONE => 1;
    use constant TAG_PARAGRAPH => 2;
    use constant TAG_BULLETLIST => 3;
    use constant TAG_DESCRIPTIONLIST => 4;
    use constant TAG_HEADING => 5;
    use constant TAG_PREFIXCODE => 6;
    use constant TAG_TAGCODE => 7;

    my %tagEnders = ( TAG_NONE() => '',
                                 TAG_PARAGRAPH() => '</p>',
                                 TAG_BULLETLIST() => '</li></ul>',
                                 TAG_DESCRIPTIONLIST() => '</dd></dl>',
                                 TAG_HEADING() => '</h>',
                                 TAG_PREFIXCODE() => '</code>',
                                 TAG_TAGCODE() => '</code>' );

    my $topLevelTag = TAG_NONE;

    my $output;
    my $textBlock;
    my $prevLineBlank = 1;

    my $codeBlock;
    my $removedCodeSpaces;

    my $ignoreListSymbols;

    my $index = $startingIndex;

    while ($index < $endingIndex)
        {
        # If we're in a tagged code section...
        if ($topLevelTag == TAG_TAGCODE)
            {
            if ($commentLines->[$index] =~ /^ *\( *(?:end|finish|done)(?: +(?:table|code|example|diagram))? *\)$/i)
                {
                $codeBlock =~ s/\n+$//;
                $output .= NaturalDocs::NDMarkup->ConvertAmpChars($codeBlock) . '</code>';
                $codeBlock = undef;
                $topLevelTag = TAG_NONE;
                $prevLineBlank = undef;
                }
            else
                {
                $self->AddToCodeBlock($commentLines->[$index], \$codeBlock, \$removedCodeSpaces);
                };
            }

        # If the line starts with a code designator...
        elsif ($commentLines->[$index] =~ /^ *[>:|](.*)$/)
            {
            my $code = $1;

            if ($topLevelTag == TAG_PREFIXCODE)
                {
                $self->AddToCodeBlock($code, \$codeBlock, \$removedCodeSpaces);
                }
            else # $topLevelTag != TAG_PREFIXCODE
                {
                if (defined $textBlock)
                    {
                    $output .= $self->RichFormatTextBlock($textBlock) . $tagEnders{$topLevelTag};
                    $textBlock = undef;
                    };

                $topLevelTag = TAG_PREFIXCODE;
                $output .= '<code>';
                $self->AddToCodeBlock($code, \$codeBlock, \$removedCodeSpaces);
                };
            }

        # If we're not in either code style...
        else
            {
            # Strip any leading whitespace.
            $commentLines->[$index] =~ s/^ +//;

            # If we were in a prefixed code section...
            if ($topLevelTag == TAG_PREFIXCODE)
                {
                $codeBlock =~ s/\n+$//;
                $output .= NaturalDocs::NDMarkup->ConvertAmpChars($codeBlock) . '</code>';
                $codeBlock = undef;
                $topLevelTag = TAG_NONE;
                $prevLineBlank = undef;
                };


            # If the line is blank...
            if (!length($commentLines->[$index]))
                {
                # End a paragraph.  Everything else ignores it for now.
                if ($topLevelTag == TAG_PARAGRAPH)
                    {
                    $output .= $self->RichFormatTextBlock($textBlock) . '</p>';
                    $textBlock = undef;
                    $topLevelTag = TAG_NONE;
                    };

                $prevLineBlank = 1;
                }

            # If the line starts with a bullet...
            elsif ($commentLines->[$index] =~ /^[-\*o+] +([^ ].*)$/)
                {
                my $bulletedText = $1;

                if (defined $textBlock)
                    {  $output .= $self->RichFormatTextBlock($textBlock);  };

                if ($topLevelTag == TAG_BULLETLIST)
                    {
                    $output .= '</li><li>';
                    }
                else #($topLevelTag != TAG_BULLETLIST)
                    {
                    $output .= $tagEnders{$topLevelTag} . '<ul><li>';
                    $topLevelTag = TAG_BULLETLIST;
                    };

                $textBlock = $bulletedText;

                $prevLineBlank = undef;
                }

            # If the line looks like a description list entry...
            elsif ($commentLines->[$index] =~ /^(.+?) +- +([^ ].*)$/)
                {
                my $entry = $1;
                my $description = $2;

                if (defined $textBlock)
                    {  $output .= $self->RichFormatTextBlock($textBlock);  };

                if ($topLevelTag == TAG_DESCRIPTIONLIST)
                    {
                    $output .= '</dd>';
                    }
                else #($topLevelTag != TAG_DESCRIPTIONLIST)
                    {
                    $output .= $tagEnders{$topLevelTag} . '<dl>';
                    $topLevelTag = TAG_DESCRIPTIONLIST;
                    };

                if ($isList && !$ignoreListSymbols)
                    {
                    $output .= '<ds>' . NaturalDocs::NDMarkup->ConvertAmpChars($entry) . '</ds><dd>';
                    }
                else
                    {
                    $output .= '<de>' . NaturalDocs::NDMarkup->ConvertAmpChars($entry) . '</de><dd>';
                    };

                $textBlock = $description;

                $prevLineBlank = undef;
                }

            # If the line could be a header...
            elsif ($prevLineBlank && $commentLines->[$index] =~ /^(.*)([^ ]):$/)
                {
                my $headerText = $1 . $2;

                if (defined $textBlock)
                    {
                    $output .= $self->RichFormatTextBlock($textBlock);
                    $textBlock = undef;
                    }

                $output .= $tagEnders{$topLevelTag};
                $topLevelTag = TAG_NONE;

                $output .= '<h>' . $self->RichFormatTextBlock($headerText) . '</h>';

                if ($type eq ::TOPIC_FUNCTION() && $isList)
                    {
                    $ignoreListSymbols = exists $functionListIgnoredHeadings{lc($headerText)};
                    };

                $prevLineBlank = undef;
                }

            # If the line looks like a code tag...
            elsif ($commentLines->[$index] =~ /^\( *(?:(?:start|begin)? +)?(?:table|code|example|diagram) *\)$/i)
                {
                if (defined $textBlock)
                    {
                    $output .= $self->RichFormatTextBlock($textBlock);
                    $textBlock = undef;
                    };

                $output .= $tagEnders{$topLevelTag} . '<code>';
                $topLevelTag = TAG_TAGCODE;
                }

            # If the line isn't any of those, we consider it normal text.
            else
                {
                # A blank line followed by normal text ends lists.  We don't handle this when we detect if the line's blank because
                # we don't want blank lines between list items to break the list.
                if ($prevLineBlank && ($topLevelTag == TAG_BULLETLIST || $topLevelTag == TAG_DESCRIPTIONLIST))
                    {
                    $output .= $self->RichFormatTextBlock($textBlock) . $tagEnders{$topLevelTag} . '<p>';

                    $topLevelTag = TAG_PARAGRAPH;
                    $textBlock = undef;
                    }

                elsif ($topLevelTag == TAG_NONE)
                    {
                    $output .= '<p>';
                    $topLevelTag = TAG_PARAGRAPH;
                    # textBlock will already be undef.
                    };

                if (defined $textBlock)
                    {  $textBlock .= ' ';  };

                $textBlock .= $commentLines->[$index];

                $prevLineBlank = undef;
                };
            };

        $index++;
        };

    # Clean up anything left dangling.
    if (defined $textBlock)
        {
        $output .= $self->RichFormatTextBlock($textBlock) . $tagEnders{$topLevelTag};
        }
    elsif (defined $codeBlock)
        {
        $codeBlock =~ s/\n+$//;
        $output .= NaturalDocs::NDMarkup->ConvertAmpChars($codeBlock) . '</code>';
        };

    return $output;
    };


#
#   Function: AddToCodeBlock
#
#   Adds a line of text to a code block, handling all the indentation processing required.
#
#   Parameters:
#
#       line - The line of text to add.
#       codeBlockRef - A reference to the code block to add it to.
#       removedSpacesRef - A reference to a variable to hold the number of spaces removed.  It needs to be stored between calls.
#                                      It will reset itself automatically when the code block codeBlockRef points to is undef.
#
sub AddToCodeBlock #(line, codeBlockRef, removedSpacesRef)
    {
    my ($self, $line, $codeBlockRef, $removedSpacesRef) = @_;

    $line =~ /^( *)(.*)$/;
    my ($spaces, $code) = ($1, $2);

    if (!defined $$codeBlockRef)
        {
        if (length($code))
            {
            $$codeBlockRef = $code . "\n";
            $$removedSpacesRef = length($spaces);
            };
        # else ignore leading line breaks.
        }

    elsif (length $code)
        {
        # Make sure we have the minimum amount of spaces to the left possible.
        if (length($spaces) != $$removedSpacesRef)
            {
            my $spaceDifference = abs( length($spaces) - $$removedSpacesRef );
            my $spacesToAdd = ' ' x $spaceDifference;

            if (length($spaces) > $$removedSpacesRef)
                {
                $$codeBlockRef .= $spacesToAdd;
                }
            else
                {
                $$codeBlockRef =~ s/^(.)/$spacesToAdd . $1/gme;
                $$removedSpacesRef = length($spaces);
                };
            };

        $$codeBlockRef .= $code . "\n";
        }

    else # (!length $code)
        {
        $$codeBlockRef .= "\n";
        };
    };


#
#   Function: RichFormatTextBlock
#
#   Applies rich <NDMarkup> formatting to a chunk of text.  This includes both amp chars, formatting tags, and link tags.
#
#   Parameters:
#
#       text - The block of text to format.
#
#   Returns:
#
#       The formatted text block.
#
sub RichFormatTextBlock #(text)
    {
    my ($self, $text) = @_;
    my $output;


    # Split the text from the potential tags.

    my @tempTextBlocks = split(/([\*_<>])/, $text);

    # Since the symbols are considered dividers, empty strings could appear between two in a row or at the beginning/end of the
    # array.  This could seriously screw up TagType(), so we need to get rid of them.
    my @textBlocks;

    while (scalar @tempTextBlocks)
        {
        my $tempTextBlock = shift @tempTextBlocks;

        if (length $tempTextBlock)
            {  push @textBlocks, $tempTextBlock;  };
        };


    my $bold;
    my $underline;
    my $underlineHasWhitespace;

    my $index = 0;

    while ($index < scalar @textBlocks)
        {
        if ($textBlocks[$index] eq '<' && $self->TagType(\@textBlocks, $index) == POSSIBLE_OPENING_TAG)
            {
            my $endingIndex = $self->ClosingTag(\@textBlocks, $index, undef);

            if ($endingIndex != -1)
                {
                my $linkText;
                $index++;

                while ($index < $endingIndex)
                    {
                    $linkText .= $textBlocks[$index];
                    $index++;
                    };
                # Index will be incremented again at the end of the loop.

                if ($linkText =~ /^(?:mailto\:)?((?:[a-z0-9\-_]+\.)*[a-z0-9\-_]+@(?:[a-z0-9\-]+\.)+[a-z]{2,4})$/i)
                    {  $output .= '<email>' . NaturalDocs::NDMarkup->ConvertAmpChars($1) . '</email>';  }
                elsif ($linkText =~ /^(?:http|https|ftp|news|file)\:/i)
                    {  $output .= '<url>' . NaturalDocs::NDMarkup->ConvertAmpChars($linkText) . '</url>';  }
                else
                    {  $output .= '<link>' . NaturalDocs::NDMarkup->ConvertAmpChars($linkText) . '</link>';  };
                }

            else # it's not a link.
                {
                $output .= '&lt;';
                };
            }

        elsif ($textBlocks[$index] eq '*')
            {
            my $tagType = $self->TagType(\@textBlocks, $index);

            if ($tagType == POSSIBLE_OPENING_TAG && $self->ClosingTag(\@textBlocks, $index, undef) != -1)
                {
                # ClosingTag() makes sure tags aren't opened multiple times in a row.
                $bold = 1;
                $output .= '<b>';
                }
            elsif ($bold && $tagType == POSSIBLE_CLOSING_TAG)
                {
                $bold = undef;
                $output .= '</b>';
                }
            else
                {
                $output .= '*';
                };
            }

        elsif ($textBlocks[$index] eq '_')
            {
            my $tagType = $self->TagType(\@textBlocks, $index);

             if ($tagType == POSSIBLE_OPENING_TAG && $self->ClosingTag(\@textBlocks, $index, \$underlineHasWhitespace) != -1)
                {
                # ClosingTag() makes sure tags aren't opened multiple times in a row.
                $underline = 1;
                #underlineHasWhitespace is set by ClosingTag().
                $output .= '<u>';
                }
            elsif ($underline && $tagType == POSSIBLE_CLOSING_TAG)
                {
                $underline = undef;
                #underlineHasWhitespace will be reset by the next opening underline.
                $output .= '</u>';
                }
            elsif ($underline && !$underlineHasWhitespace)
                {
                # If there's no whitespace between underline tags, all underscores are replaced by spaces so
                # _some_underlined_text_ becomes <u>some underlined text</u>.  The standard _some underlined text_
                # will work too.
                $output .= ' ';
                }
            else
                {
                $output .= '_';
                };
            }

        else # plain text or a > that isn't part of a link
            {
            $output .= NaturalDocs::NDMarkup->ConvertAmpChars($textBlocks[$index]);;
            };

        $index++;
        };


    # Pull out the e-mail addresses and URLs that aren't in angle brackets.  Preventing > from being the leading character will
    # prevent it from duplicating <url> and <email> tags, although I don't know if it may be falsely triggered in other situations
    # as well.

    $output =~ s{
                        # The previous character can't be an alphanumeric.
                        (?<!  [a-z0-9>]  )

                        # Optional mailto:.  Ignored in output.
                        (?:mailto\:)?

                        # Begin capture
                        (

                        # The user portion.  Alphanumeric and - _.  Dots can appear between, but not at the edges or more than
                        # one in a row.
                        (?:  [a-z0-9\-_]+  \.  )*   [a-z0-9\-_]+

                        @

                        # The domain.  Alphanumeric and -.  Dots same as above, however, there must be at least two sections
                        # and the last one must be two to four alphanumeric characters (.com, .uk, .info, .203 for IP addresses)
                        (?:  [a-z0-9\-]+  \.  )+  [a-z]{2,4}

                        # End capture.
                        )

                        # The next character can't be an alphanumeric, which should prevent .abcde from matching the two to
                        # four character requirement.
                        (?!  [a-z0-9]  )

                        }

                   {<email>$1<\/email>}igx;

    $output =~ s{
                        # The previous character can't be an alphanumeric.
                        (?<!  [a-z0-9>]  )

                        # Begin capture.
                        (

                        # URL must start with one of the acceptable protocols.
                        (?:http|https|ftp|news|file)\:

                        # The acceptable URL characters as far as I know.
                        [a-z0-9\-\=\~\@\#\%\&\_\+\/\;\:\?\.\,]*

                        # The URL characters minus period and comma.  If it ends on them, they're probably intended as punctuation.
                        [a-z0-9\-\=\~\@\#\%\&\_\+\/\;\:\?]

                        # End capture.
                        )

                        # The next character must not be an acceptable character.  This will prevent the URL from ending early just
                        # to get a match.
                        (?!  [a-z0-9\-\=\~\@\#\%\&\_\+\/\;\:\?]  )

                        }
                       {<url>$1<\/url>}igx;

    return $output;
    };


#
#   Function: TagType
#
#   Returns whether the tag is a possible opening or closing tag, or neither.  "Possible" because it doesn't check if an opening tag is
#   closed or a closing tag is opened, just whether the surrounding characters allow it to be a candidate for a tag.  For example, in
#   "A _B" the underscore is a possible opening underline tag, but in "A_B" it is not.  Support function for <RichFormatTextBlock()>.
#
#   Parameters:
#
#       textBlocks  - A reference to an array of text blocks.
#       index         - The index of the tag.
#
#   Returns:
#
#       POSSIBLE_OPENING_TAG, POSSIBLE_CLOSING_TAG, or NOT_A_TAG.
#
sub TagType #(textBlocks, index)
    {
    my ($self, $textBlocks, $index) = @_;


    # Possible opening tags

    if ( ( $textBlocks->[$index] =~ /^[\*_<]$/ ) &&

        # Before it must be whitespace, the beginning of the text, or ({["'-/.
        ( $index == 0 || $textBlocks->[$index-1] =~ /[\ \t\n\(\{\[\"\'\-\/]$/ )&&

        # After it must be non-whitespace.
        ( $index + 1 < scalar @$textBlocks && $textBlocks->[$index+1] !~ /^[\ \t\n]/) &&

        # Make sure we don't accept <<, <=, <-, or *= as opening tags
        ( $textBlocks->[$index] ne '<' || $textBlocks->[$index+1] !~ /^[<=-]/ ) &&
        ( $textBlocks->[$index] ne '*' || $textBlocks->[$index+1] !~ /^\=/ ) )
        {
        return POSSIBLE_OPENING_TAG;
        }


    # Possible closing tags

    elsif ( ( $textBlocks->[$index] =~ /^[\*_>]$/) &&

            # After it must be whitespace, the end of the text, or )}].,!?"';:-/.
            ( $index + 1 == scalar @$textBlocks || $textBlocks->[$index+1] =~ /^[ \t\n\)\]\}\.\,\!\?\"\'\;\:\-\/]/ ||
              # Links also get plurals, like <link>s, <linx>es, <link>'s, and <links>'.
              ( $textBlocks->[$index] eq '>' && $textBlocks->[$index+1] =~ /^(?:es|s|\')/ ) ) &&

            # Before it must be non-whitespace.
            ( $index != 0 && $textBlocks->[$index-1] !~ /[ \t\n]$/ ) &&

            # Make sure we don't accept >>, ->, or => as closing tags.  >= is already taken care of.
            ( $textBlocks->[$index] ne '>' || $textBlocks->[$index-1] !~ /[>=-]$/ ) )
        {
        return POSSIBLE_CLOSING_TAG;
        }

    else
        {
        return NOT_A_TAG;
        };

    };


#
#   Function: ClosingTag
#
#   Returns whether a tag is closed or not, where it's closed if it is, and optionally whether there is any whitespace between the
#   tags.  Support function for <RichFormatTextBlock()>.
#
#   The results of this function are in full context, meaning that if it says a tag is closed, it can be interpreted as that tag in the
#   final output.  It takes into account any spoiling factors, like there being two opening tags in a row.
#
#   Parameters:
#
#       textBlocks             - A reference to an array of text blocks.
#       index                    - The index of the opening tag.
#       hasWhitespaceRef  - A reference to the variable that will hold whether there is whitespace between the tags or not.  If
#                                     undef, the function will not check.  If the tag is not closed, the variable will not be changed.
#
#   Returns:
#
#       If the tag is closed, it returns the index of the closing tag and puts whether there was whitespace between the tags in
#       hasWhitespaceRef if it was specified.  If the tag is not closed, it returns -1 and doesn't touch the variable pointed to by
#       hasWhitespaceRef.
#
sub ClosingTag #(textBlocks, index, hasWhitespace)
    {
    my ($self, $textBlocks, $index, $hasWhitespaceRef) = @_;

    my $hasWhitespace;
    my $closingTag;

    if ($textBlocks->[$index] eq '*' || $textBlocks->[$index] eq '_')
        {  $closingTag = $textBlocks->[$index];  }
    elsif ($textBlocks->[$index] eq '<')
        {  $closingTag = '>';  }
    else
        {  return -1;  };

    my $beginningIndex = $index;
    $index++;

    while ($index < scalar @$textBlocks)
        {
        if ($textBlocks->[$index] eq '<' && $self->TagType($textBlocks, $index) == POSSIBLE_OPENING_TAG)
            {
            # If we hit a < and we're checking whether a link is closed, it's not.  The first < becomes literal and the second one
            # becomes the new link opening.
            if ($closingTag eq '>')
                {
                return -1;
                }

            # If we're not searching for the end of a link, we have to skip the link because formatting tags cannot appear within
            # them.  That's of course provided it's closed.
            else
                {
                my $linkHasWhitespace;

                my $endIndex = $self->ClosingTag($textBlocks, $index,
                                                                    ($hasWhitespaceRef && !$hasWhitespace ? \$linkHasWhitespace : undef) );

                if ($endIndex != -1)
                    {
                    if ($linkHasWhitespace)
                        {  $hasWhitespace = 1;  };

                    # index will be incremented again at the end of the loop, which will bring us past the link's >.
                    $index = $endIndex;
                    };
                };
            }

        elsif ($textBlocks->[$index] eq $closingTag)
            {
            my $tagType = $self->TagType($textBlocks, $index);

            if ($tagType == POSSIBLE_CLOSING_TAG)
                {
                # There needs to be something between the tags for them to count.
                if ($index == $beginningIndex + 1)
                    {  return -1;  }
                else
                    {
                    # Success!

                    if ($hasWhitespaceRef)
                        {  $$hasWhitespaceRef = $hasWhitespace;  };

                    return $index;
                    };
                }

            # If there are two opening tags of the same type, the first becomes literal and the next becomes part of a tag.
            elsif ($tagType == POSSIBLE_OPENING_TAG)
                {  return -1;  }
            }

        elsif ($hasWhitespaceRef && !$hasWhitespace)
            {
            if ($textBlocks->[$index] =~ /[ \t\n]/)
                {  $hasWhitespace = 1;  };
            };

        $index++;
        };

    # Hit the end of the text blocks if we're here.
    return -1;
    };


1;
