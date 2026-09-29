# The README demo. Record it with: python3 demo/record.py

Output nurl-demo.mp4
Output nurl-demo.webm

Set Shell "bash"
Set FontFamily "JetBrainsMono Nerd Font"
Set FontSize 19
Set Width 1600
Set Height 940
Set Padding 18
Set Margin 28
Set MarginFill "#6e6a86"
Set WindowBar Colorful
Set BorderRadius 10
Set TypingSpeed 55ms
Set Framerate 30
Set Theme { "name": "rose-pine", "black": "#26233a", "red": "#eb6f92", "green": "#31748f", "yellow": "#f6c177", "blue": "#9ccfd8", "magenta": "#c4a7e7", "cyan": "#ebbcba", "white": "#e0def4", "brightBlack": "#6e6a86", "brightRed": "#eb6f92", "brightGreen": "#31748f", "brightYellow": "#f6c177", "brightBlue": "#9ccfd8", "brightMagenta": "#c4a7e7", "brightCyan": "#ebbcba", "brightWhite": "#e0def4", "background": "#191724", "foreground": "#e0def4", "selection": "#403d52", "cursor": "#524f67" }

Hide
Type "cd project && nvim -u ../init.lua .nurl/users.lua" Enter
Sleep 2.5s
Show
Sleep 2s

# 1. Send the request at the cursor, then look through its tabs
Type "6G"
Sleep 600ms
Type ":Nurl ."
Sleep 500ms
Enter
Sleep 3s
Ctrl+W
Type "l"
Sleep 600ms
Tab
Sleep 2s
Tab
Sleep 3s
Tab
Sleep 1.2s
Tab
Sleep 1.2s
Tab
Sleep 3.5s
Type "q"
Sleep 1s

# 2. Pick any request of the project
Type ":Nurl"
Sleep 400ms
Enter
Sleep 1.5s
Type "order"
Sleep 2.5s
Enter
Sleep 3s
Ctrl+W
Type "l"
Type "q"
Sleep 1s

# 3. Override a field from the command line
Type "24G"
Sleep 600ms
Type `:Nurl . data.title="Sent from the command line"`
Sleep 600ms
Enter
Sleep 3.5s
Ctrl+W
Type "l"
Type "q"
Sleep 1s

# 4. Switch to production, which asks before sending
Type ":Nurl env production"
Sleep 500ms
Enter
Sleep 1s
Type "19G"
Sleep 500ms
Type ":Nurl ."
Sleep 400ms
Enter
Sleep 2s
Enter
Sleep 3.5s
Ctrl+W
Type "l"
Type "q"
Sleep 1s

# 5. Everything sent is in the history, with its response
Type ":Nurl history"
Sleep 500ms
Enter
Sleep 2.5s
Type "j"
Sleep 1.2s
Type "j"
Sleep 1.2s
Type "k"
Sleep 1.2s
Enter
Sleep 4s
