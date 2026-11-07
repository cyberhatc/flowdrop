$env:Path = "C:\Program Files\Git\cmd;C:\Program Files\GitHub CLI;" + $env:Path
gh repo create cyberhatc/flowdrop --public --description "Fast, secure LAN file and text transfer between any devices" --source=. --push
