# fish-cd-ranger

[Ranger](https://github.com/ranger/ranger) integration for fish shell.

![screenshot](./SCREENSHOT.svg)

## Features

- `cd-ranger` command to pick a new working directory with `ranger`.
- Hotkey to change the working directory to a `ranger` bookmark.




## Install

With [fisher](https://github.com/jorgebucaran/fisher):

```fish
fisher add eth-p/fish-cd-ranger
```

### Hotkey Support

If you want to change directory to `ranger` bookmarks with a hotkey, add the following to your `config.fish` file:

```fish
bind \cs 'cd-ranger --bookmark-hotkey' 
```

