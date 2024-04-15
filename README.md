 ```
_    _  _ ___  _ ____ ____ ____ ____ _ ___ _   _ 
|    |  | |  \ | |    |__/ |  | [__  |  |   \_/  
|___ |__| |__/ | |___ |  \ |__| ___] |  |    |   

A Static Site Generator in Zig
 ```

# Installation

> To ensure seamless builds please download the dev release of the zig compiler

```bash
zig build -Doptimize=ReleaseSafe
```

# Project Structure
Ludicrosity looks for the following source tree:

```
.
├── markdwns
│   └── post0.md
├── tags(coming soon)
└── template
    └── template.html

```

## Metamatter
Ludicrosity uses a flavor of metadata inspired from [Pandoc](https://pandoc.org/) that I've designated as Metamatter. Goes something like this:

```md
% title: Post0
% author: myname
% date: 17/09/1991
% tags: new,post,exciting,fast,supreme
```

... and you write the rest of the post in good ol' markdown.

## Templating
No need to learn a new syntax for templating. No. Just use HTML Comments like so:

```html
<body>
.
.
<!--title-->
.
<!--date-->
..<!--author-->

<!--BODY-->
</body>
```

>  For metamatter fields remember to employ same naming conventions within template comments. `BODY` is reserved for post content.
