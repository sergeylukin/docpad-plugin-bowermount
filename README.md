# bower-mount Plugin for [DocPad](http://docpad.org)
DocPad plugin that auto-mounts bower components in web server middleware (currently
only JS components). Best fits for development environment. Assumes that in
production environment JS files are bundled in static files.

It's enabled only in development environment by default


## Install

Install it from you Docpad project:

```
npm install docpad-plugin-bowermount --save-dev
```

Next time you run `docpad run` your bower components will be available via web.

For example, if you installed `jquery` via `bower install jquery` and `docpad
run` creates server accessible via `http://localhost:9778` you can
access `jquery` lib via `http://localhost:9778:/scripts/jquery.js`

You'd probably want to bundle your components into static
files on build step and use this plugin to cleap your project directory clean

**RequireJS**: if you're using `RequireJS` you can set relative path to your
configuration file in `rjsConfig` (default value is `scripts/main.js`)
and if it exists, paths from there will be used to determine components path.
Here is an example of your `docpad.coffee` with this configuration:

```
# ==================
# Environment
environments:
  development:
    plugins:
      bowermount:
        rjsConfig: 'path/to/my/requirejs/config'
```


## History
You can discover the history inside the `History.md` file



## License

Licensed under the incredibly [permissive](http://en.wikipedia.org/wiki/Permissive_free_software_licence) [MIT License](http://creativecommons.org/licenses/MIT/)
<br/>Copyright &copy; 2013+ [Sergey Lukin](http://sergeylukin.com)
