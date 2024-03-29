# fish-cd-ranger | Copyright (C) 2021 eth-p
# Ranger integrations for fish shell.
#
# Documentation: https://github.com/eth-p/fish-cd-ranger/tree/master/README.md
# Repository:    https://github.com/eth-p/fish-cd-ranger
# Issues:        https://github.com/eth-p/fish-cd-ranger/issues

function cd-ranger --description="Change directory using ranger"
	argparse \
		-x 'bookmark,bookmark-hotkey,navigate,list-bookmarks' \
		'm/bookmark' 'bookmark-hotkey' 'list-bookmarks' 'navigate' \
		-- $argv || return 1
	
	set -l arg "$argv[1]"

	# Option: --list-bookmarks
	if [ -n "$_flag_list_bookmarks" ]
		__cdranger_bookmarks --absolute --delimiter=(printf "\t")
		return $status
	end

	# Option: --bookmark-hotkey
	# Use a prompt to select the bookmark.
	if [ -n "$_flag_bookmark_hotkey" ]
		set _flag_bookmark "--bookmark"
		set arg (__cdranger_bookmark_hotkey) || return $status
		set arg (string trim "$arg")
	end

	# Option: --bookmark
	# Navigate to a bookmark.
	if [ -n "$_flag_bookmark" ]
		if [ -z "$arg" ]
			echo "cd-ranger: Requires bookmark name" 1>&2
			return 1
		end

		# Find the bookmark.
		set -l mark_path (__cdranger_bookmarks --absolute --get="$arg") || begin
			printf "cd-ranger: Unknown bookmark '%s'\n" "$arg" 1>&2
			return 1
		end

		# Change the directory.
		cd "$mark_path"
		return 0
	end

	# Option: --navigate (or no options)
	# Use ranger to navigate to a new working directory.
	if true || [ -n "$_flag_naviate" ]
		set -l tempfile (mktemp)
		pwd > "$tempfile"

		# Set the title in case this is called by a keybind.
		printf "\x1B]0;ranger %s\b" (pwd)

		# Open ranger as a file picker.
		ranger --show-only-dirs --choosedir="$tempfile" \
			--cmd="set collapse_preview true" \
			--cmd="set preview_directories false" \
			--cmd="set preview_files false" \
			--cmd="set preview_images false" \
			--cmd="set padding_right false" \
			--cmd="set column_ratios 1,2,0" \
			|| return $status

		set -l newdir (cat "$tempfile")
		rm "$tempfile"
		cd "$newdir"
		return $status
	end
end

function __cdranger_cleanpath --description="normalizes a path"
	set -l cwd (string split "/" (pwd))
	set -l pathc
	for pathc in $argv
		set -l components (string split "/" (string replace --regex "/{2,}" "/" $pathc))
		set -l i 2
		
		# If not absolute path, prepend the working directory.
		if [ $components[1] != "" ]
			set split $cwd $components
		end

		# Resolve parent and self-directory components.
		while [ $i -le (count $components) ]
			switch $components[$i]
				case "."
					set components \
						$components[1..(math $i - 1)] \
						$components[(math $i + 1)..]
					
				case ".."
					if [ $i = 2 ]
						# Already at root.
						set i (math $i + 1)
						set components $components[1] ".." $components[2..]
					else
						# Remove parent.
						set components \
							$components[1..(math $i - 2)] \
							$components[(math $i + 1)..]

						set i (math $i - 1)
					end

				case '*'
					set i (math $i + 1)
			end
		end
		
		# Print the result.
		set -l cleaned (string join "/" $components)
		if [ "$cleaned" = "" ]
			set cleaned "/"
		end

		printf "%s\n" $cleaned
	end
end

function __cdranger_relpath --description="determines a relative path"
	set -l from (string sub -s 2 (__cdranger_cleanpath $argv[1]))
	set -l to   (string sub -s 2 (__cdranger_cleanpath $argv[2]))

	# Find a common prefix.
	set -l prefix
	set -l component
	set -l from_components (string split "/" $from)
	set -l to_components   (string split "/" $to)

	set -l i 0
	for component in $from_components
		set i (math $i + 1)
		if [ $component = "$to_components[$i]" ]
			set prefix $prefix $component
		end
	end

	set prefix (string join "/" $prefix)

	# Remove the common prefix.
	set prefix_len (math (string length $prefix) + 2)
	set from (string sub -s $prefix_len $from)
	set to (string sub -s $prefix_len $to)

	printf "%s%s\n" \
		(string repeat --count (count (string split "/" $from)) "../") \
		$to
end

function __cdranger_bookmarks --description="list ranger bookmarks"
	argparse \
		-x "relative,absolute" -x "get,without-values,delimiter" \
		"d/delimiter=" "relative" "absolute" "get=" \
		"without-values" "without-auto" "without-pwd" -- $argv

	# Set the default delimiter.
	if [ -z "$_flag_delimiter" ]
		set _flag_delimiter ":"
	end

	# Find all the bookmark files.
	set -l bookmark_files
	for dir in (string split -- ":" "$XDG_DATA_DIRS") "$HOME/.local/share"
		if [ -f "$dir/ranger/bookmarks" ]
			set bookmark_files $bookmark_files "$dir/ranger/bookmarks"
			continue
		end
	end

	if [ (count $bookmark_files) -eq 0 ]
		return 1
	end

	# Print the bookmarks in the bookmark files.
	set -l bookmarks_printed
	set -l file
	set -l pwd (pwd)
	set -l home_length (string length -- "$HOME")
	for file in $bookmark_files
		while read -l line
			set -l split (string split --max=1 -- ':' "$line")
			set -l mark_name "$split[1]"
			set -l mark_path "$split[2]"

			# Don't print multiple bookmarks with the same name.
			if contains -- "$mark_name" $bookmarks_printed
				continue
			end
			set bookmarks_printed $bookmarks_printed "$mark_name"

			# If --without-auto is set, ignore the ' bookmark.
			if [ "$mark_name" = "'" ] && [ -n "$_flag_without_auto" ]
				continue
			end

			# If --without-pwd is set, ignore bookmarks that are the pwd.
			if [ "$mark_path" = "$pwd" ] && [ -n "$_flag_without_pwd" ]
				continue
			end

			# If --without-values is set, just print the name.
			if [ -n "$_flag_without_values" ]
				printf "%s\n" "$mark_name"
				continue
			end

			# Use the relative path if it's shorter or if --relative is set.
			if [ -z "$_flag_absolute" ]
				set -l mark_path_relative (__cdranger_relpath "$pwd" "$mark_path")
				if [ -n "$_flag_relative" ]
					set mark_path "$mark_path_relative"
				else
					# Substitute $HOME with ~.
					if [ (string sub --length="$home_length" "$mark_path") = "$HOME" ]
						if [ "$mark_path" != "$HOME" ]
							set mark_path (printf "~%s" \
								(string sub --start=(math $home_length + 1) "$mark_path")
							)
						end
					end

					# If the relative path is shorter, use that.
					if [ (string length -- "$mark_path_relative") -lt (string length -- "$mark_path") ]
						# Ensure we don't have a chain of ../../
						if ! string match -q --regex -- '^(\.\./)+\.\./?$' "$mark_path_relative"
							set mark_path "$mark_path_relative"
						end
					end
				end
			end
			
			# If --get is set, return the bookmark path if it's the right bookmark.
			if [ -n "$_flag_get" ]
				if [ "$_flag_get" != "$mark_name" ]
					continue
				end

				printf "%s\n" "$mark_path"
				return 0
			end

			# Print the name and path.
			printf "%s%s%s\n" "$mark_name" "$_flag_delimiter" "$mark_path"
		end < "$file"
	end

	if [ -n "$_flag_get" ]
		return 1
	end

	return 0
end

function __cdranger_bookmark_hotkey
	argparse -x 'max-display-lines,max-display-percent' \
		'no-display' 'max-display-percent' 'max-display-lines' \
		-- $argv || return 1
	
	if [ -n "$_flag_no_display" ]
		bash -c 'trap "exit 2" INT; read -srn1 -p "" x && echo "$x"; exit 0'
		return $status
	end

	# Get the size of the terminal.
	set -l term_size (string split -- ' ' (stty size))
	set -l term_cols "$term_size[2]"
	set -l term_rows "$term_size[1]"

	# Get the cursor position.
	set -l dsr (bash -c 'printf "\x1B[6n" >>/dev/tty; read -sr -d "R" x; printf "%sR" "$x"' </dev/tty) \
	|| begin
		__cdranger_bookmark_hotkey --no-display
		return $status
	end

	# Parse the cursor position.
	set -l dsr_values (string match --regex '\[(\d+);(\d+)R' -- "$dsr") || begin
		__cdranger_bookmark_hotkey --no-display
		return $status
	end

	set -l curs_row "$dsr_values[2]"
	set -l curs_col "$dsr_values[3]"

	# Get the list of bookmarks.
	set -l bookmarks (__cdranger_bookmarks --delimiter=(printf "\t") --without-pwd) || begin
		__cdranger_bookmark_hotkey --no-display
		return $status
	end

	set -l bookmarks_count (count $bookmarks)

	# Determine how many lines we can use for the hint display.
	set -l max_allowed_lines "$_flag_max_display_lines"
	if [ -z "$max_allowed_lines" ]
		[ -n "$_flag_max_display_percent" ] || set _flag_max_display_percent "20"
		set max_allowed_lines (math "$_flag_max_display_percent" / 100 '*' "$term_rows")
	end

	# Determine how many lines we are actually using for the hint display.
	set -l max_lines "$bookmarks_count"
	if [ "$max_allowed_lines" -lt "$max_lines" ]
		set max_lines "$max_allowed_lines"
	end

	# Determine how many lines we need to add to the terminal.
	set -l free_lines (math "$term_rows" - "$curs_row")
	set -l needed_lines (math "$max_lines" + 1)
	set -l added_lines (math "$needed_lines" - "$free_lines")
	if [ "$added_lines" -lt 0 ]
		set added_lines 0
	end

	# Hide the cursor.
	printf "\x1B[?25l" 1>&2

	# If lines need to be added, use 'CSI n S' to add lines to the bottom.
	if [ "$added_lines" -gt 0 ]
		printf "\x1B[%sS" "$added_lines" 1>&2
		printf "\x1B[%sA" (math $added_lines - 1) 1>&2

		# Workaround for an edge case.
		if [ "$added_lines" -eq 1 ]
			printf "\x1B[B" 1>&2
		end
	else
		printf "\x1B[B" 1>&2
	end

	# Set the cursor position to the beginning of the line.
	printf "\x1B[G" 1>&2

	# Draw the hint header and bookmarks.
	begin
		printf "\x1B[0;4m%-$term_cols""s\x1B[0m\n" "mark    path"
		set -l i
		for i in (seq 1 $max_lines)
			printf "%s\x1B[G\x1B[B" "$bookmarks[$i]" 
		end
	end 1>&2

	# Prompt the user.
	set -l response (__cdranger_bookmark_hotkey --no-display)
	set -l response_status $status

	# Clear the hints.
	begin
		printf "\x1B[G"
		for i in (seq 0 $max_lines)
			printf "\x1B[K\x1B[A"
		end
		printf "\x1B[K"
	end 1>&2

	# Move the cursor back to its original line.
	if [ "$added_lines" -eq 0 ] && [ "$needed_lines" != "$free_lines" ]
		printf "\x1B[A" 1>&2
	end

	# Redraw the prompt.
	commandline -f repaint

	# Show the cursor.
	printf "\x1B[?25h" 1>&2
	
	# Return the result.
	if [ "$response" = (printf "\x1B") ]
		return 1
	end

	echo "$response"
	return $response_status
end

