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

function __cdranger_bookmarks --description="list ranger bookmarks"
	argparse \
		-x "relative,absolute" -x "get,without-values,delimiter" \
		"d/delimiter=" "without-values" "relative" "absolute" "get=" -- $argv

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

			# If --without-values is set, just print the name.
			if [ -n "$_flag_without_values" ]
				printf "%s\n" "$mark_name"
				continue
			end

			# Use the relative path if it's shorter or if --relative is set.
			if [ -z "$_flag_absolute" ]
				set -l mark_path_relative (realpath --relative-to="$pwd" "$mark_path")
				if [ -n "$_flag_relative" ]
					set mark_path "$mark_path_relative"
				else if [ (string length -- "$mark_path_relative") -lt (string length -- "$mark_path") ]
					set mark_path "$mark_path_relative"
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
	set -l bookmarks (__cdranger_bookmarks --delimiter=(printf "\t")) || begin
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
	set -l free_lines (math "$term_rows" - "$curs_row" - 1)
	set -l added_lines (math "$max_lines" - "$free_lines")
	if [ "$added_lines" -lt 0 ]
		set added_lines 0
	end

	# Hide the cursor.
	printf "\x1B[?25l" 1>&2

	# If lines need to be added, use 'CSI n S' to add lines to the bottom.
	if [ "$added_lines" -gt 0 ]
		printf "\x1B[%sS" "$added_lines" 1>&2
		printf "\x1B[%sA" "$added_lines" 1>&2
	end

	# Set the cursor position to the beginning of the line.
	printf "\x1B[G" 1>&2

	# Draw the hint header and bookmarks.
	begin
		printf "\x1B[0;4m%-$term_cols""s\x1B[0m\n" "mark    path"
		set -l i
		for i in (seq 1 $max_lines)
			printf "%s\n" "$bookmarks[$i]" 
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

	# Redraw the prompt.
	commandline -f repaint

	# Show the cursor.
	printf "\x1B[?25h" 1>&2
	
	# Return the result.
	echo "$response"
	return $response_status
end

