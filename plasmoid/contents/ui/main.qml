import QtQuick 2.0
import QtQuick.Layouts 1.1
import QtQuick.Controls 1.4

import org.kde.plasma.components 2.0 as PlasmaComponents
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.kquickcontrolsaddons 2.0

Item {
    id: root
    
    Plasmoid.preferredRepresentation: isConstrained() ? Plasmoid.compactRepresentation : Plasmoid.fullRepresentation
    //Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    Plasmoid.compactRepresentation: CompactRepresentation {}
    Plasmoid.fullRepresentation: FullRepresentation {}
    
    property int interval;    
    property int dropdownItemsCount: -1;
    
    function isConstrained() {
        return (plasmoid.formFactor == PlasmaCore.Types.Vertical || plasmoid.formFactor == PlasmaCore.Types.Horizontal);
    }

    property var command: plasmoid.configuration.command
    
    onCommandChanged: {
        update();
    }

    Component.onCompleted: {        
        timer.running = true;     
    }
    
    function update() {
        if (command === '') {
            plasmoid.setConfigurationRequired(true, 'You need to provide a command');
            
        } else {
            plasmoid.setConfigurationRequired(false);
        }
        //dropdownItemsCount = 0;
        commandResultsDS.exec(command);
        updateInterval();
    }
    
    function updateInterval() {
        var commandTokens = command.split('.');
            
        if (commandTokens.length >= 3) {
            var intervalToken = commandTokens[commandTokens.length - 2]; //ex: 1s
            
            
            if (/^[0-9]+[smhd]$/.test(intervalToken)) {
                var lastChar = intervalToken.charAt(intervalToken.length-1);
                switch (lastChar) {
                    case 's': timer.interval = parseInt(intervalToken.slice(0, -1)) * 1000; break;
                    case 'm': timer.interval = parseInt(intervalToken.slice(0, -1)) * 1000 * 60; break;
                    case 'h': timer.interval = parseInt(intervalToken.slice(0, -1)) * 1000 * 3600; break;
                    case 'd': timer.interval = parseInt(intervalToken.slice(0, -1)) * 1000 * 3600 * 24; break;
                }
            }
        } else {
            timer.interval = plasmoid.configuration.interval * 1000
        }
    }
    
    
    function parseLine(line, currentCategory) {
        var parsedObject = {title: line};
        
        if (line.indexOf('|') != -1) {
            parsedObject.title = line.split('|')[0].trim();
            
            var attributesToken = line.split('|')[1].trim();
            
            attributesToken.split(" ").forEach(function(attribute_value) {
                
                if (attribute_value.indexOf('=')!=-1) {
                    parsedObject[attribute_value.split('=')[0]] = attribute_value.substring(attribute_value.indexOf('=') + 1);
                }
            });
        }
        
        if (parsedObject.title.match(/^--/)) {
            parsedObject.title = parsedObject.title.substring(2).trim();
            if (currentCategory !== undefined) {
                parsedObject.category = currentCategory;
            }
        }
        return parsedObject;
    }
    
    function parseItems(stdout) {
        var items = [];
        var currentCategory = null;
        
        var menuGroupsStrings = stdout.split("---");
        
        var totalItems = 0;
        if (menuGroupsStrings.length > 1) {
            
            for (var i = 1; i < menuGroupsStrings.length; i++) {
                var groupString = menuGroupsStrings[i];
                
                var groupTokens = groupString.trim().split('\n');
                groupTokens.forEach(function (groupToken) {                
                    var parsedItem = root.parseLine(groupToken, currentCategory);
                    if (parsedItem.category === undefined) {
                        currentCategory = parsedItem.title;
                    }
                    items.push(parsedItem);
                    totalItems ++;
                    
                });                
            }            
        }
        return items;
    }
    
    // DataSource for the user command execution results
    PlasmaCore.DataSource {
        id: commandResultsDS
        engine: "executable"
        connectedSources: []
        onNewData: {
                var stdout = data["stdout"]
                exited(sourceName, stdout)
                disconnectSource(sourceName) // cmd finished
        }
        
        function exec(cmd) {
                connectSource(cmd)
        }
        signal exited(string sourceName, string stdout)

    }
    
    // Generic DataSource to execute internal kargo commands (like running bash 
    // attribute or open the browser with href)
    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})
        onNewData: {
            var stdout = data["stdout"]
            
            if (callbacks[sourceName] !== undefined) {
                callbacks[sourceName](stdout);
            }
            
            exited(sourceName, stdout)
            disconnectSource(sourceName) // cmd finished
        }
        
        function exec(cmd, onNewDataCallback) {
            if (onNewDataCallback !== undefined){
                callbacks[cmd] = onNewDataCallback
            }
            connectSource(cmd)
                    
        }
        signal exited(string sourceName, string stdout)

    }
    
    property var imagesIndex: ({})
    
    function createImageFile(base64, callback) {
            var filename = imagesIndex[base64];
            if (filename === undefined) {
                executable.exec('/bin/bash -c \'file=$(mktemp /tmp/kargos.image.XXXXXX); echo "'+base64+'" | base64 -d > $file; echo -n $file\'', function(filename) {
                    imagesIndex[base64] = filename;
                    callback(filename);
                });
            } else {
                callback(filename);
            }
            
    }
    
    Connections {
        target: commandResultsDS
        onExited: {
            dropdownItemsCount = parseItems(stdout).filter(
                function(item) {
                    return item.dropdown === undefined || item.dropdown !== 'false'
                }).length;
                
            if (stdout.indexOf('---') === -1) {
                plasmoid.expanded = false
            }
        }
    }
    
    Timer {
        id: timer
        interval: plasmoid.configuration.interval * 1000
        running: false
        repeat: true
        onTriggered: update()
    }    
}
