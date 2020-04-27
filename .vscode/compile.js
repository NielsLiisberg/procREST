var fs = require('fs');
var http = require('http');

var opt =   JSON.parse(fs.readFileSync('./.vscode/opt.json', 'utf8'));
var userFile = process.argv[2];
var sourceFile = process.argv[3];
var format = process.argv[4];

var file = userFile;
if (opt.root) {
    var rootPosition = file.toLowerCase().indexOf(opt.root.toLowerCase());
    if (rootPosition > -1) {
        file = file.substring(rootPosition);
    }
}
// Don't log anythng else but the responst: it will fail on windows 10
// console.log("Submitting file " + file + " to " + opt.server + " (" + opt.id + ")");

var host = opt.server + '/.2/system/crticepgm?';
var purl  = "userFile=" + userFile + "&format=" + format + "&source=" + sourceFile;
var serverid   =  '&server=' + opt.id;
var n= host + purl + serverid;

var p = http.get(n, function(response) {
    response.on('data', function(d) {
        process.stdout.write(d);
    });
    response.on('end', function() {
        process.stdout.write("\nDone");
    });
});
