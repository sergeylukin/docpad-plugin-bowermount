# bower-mount Plugin for [DocPad](http://docpad.org)
DocPad plugin that mounts bower components in web server middleware (currently
only JS components)



## Install

Make sure you have `bower` install globally.

Install it from you Docpad project:

```
npm install docpad-plugin-bowermount --save-dev
```

Next time you run `docpad run` your bower components will be available via web.

For example, if you installed `jquery` via `bower install jquery` and `docpad
run` creates server accessible via `http://localhost:9778` you can
access `jquery` lib via `http://localhost:9778:/scripts/jquery.js`

With that being said, you'd probably want bundle your components into static
files on build step or enabling this plugin on production (which is less
likely)



## History
You can discover the history inside the `History.md` file



## License

Licensed under the incredibly [permissive](http://en.wikipedia.org/wiki/Permissive_free_software_licence) [MIT License](http://creativecommons.org/licenses/MIT/)
<br/>Copyright &copy; 2013+ [Sergey Lukin](http://sergeylukin.com)
