#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const CONFIG_FILE = path.join(__dirname, '..', '.local-config.json');

const DEFAULT_PATHS = {
    gitBash: [
        'C:/Program Files/Git/bin/bash.exe',
        'C:/Program Files (x86)/Git/bin/bash.exe'
    ],
    sevenZip: [
        'C:/Program Files/7-Zip/7z.exe',
        'C:/Program Files (x86)/7-Zip/7z.exe'
    ],
    factorio: [
        'C:/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe',
        'C:/Program Files/Steam/steamapps/common/Factorio/bin/x64/factorio.exe'
    ]
};

function findPath(candidates) {
    for (const p of candidates) {
        if (fs.existsSync(p)) {
            return p;
        }
    }
    return null;
}

async function prompt(rl, question, defaultValue) {
    return new Promise(resolve => {
        const displayDefault = defaultValue ? ` [${defaultValue}]` : '';
        rl.question(`${question}${displayDefault}: `, answer => {
            resolve(answer.trim() || defaultValue || '');
        });
    });
}

async function main() {
    console.log('AutoGhostBuilder Setup\n');

    const existingConfig = fs.existsSync(CONFIG_FILE)
        ? JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'))
        : {};

    const detected = {
        gitBash: findPath(DEFAULT_PATHS.gitBash),
        sevenZip: findPath(DEFAULT_PATHS.sevenZip),
        factorio: findPath(DEFAULT_PATHS.factorio)
    };

    console.log('Detected paths:');
    console.log(`  Git Bash: ${detected.gitBash || 'not found'}`);
    console.log(`  7-Zip:    ${detected.sevenZip || 'not found'}`);
    console.log(`  Factorio: ${detected.factorio || 'not found'}`);
    console.log('');

    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    const config = {
        gitBash: await prompt(rl, 'Git Bash path', existingConfig.gitBash || detected.gitBash),
        sevenZip: await prompt(rl, '7-Zip path', existingConfig.sevenZip || detected.sevenZip),
        factorio: await prompt(rl, 'Factorio path', existingConfig.factorio || detected.factorio)
    };

    rl.close();

    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2) + '\n');
    console.log(`\nConfig saved to ${CONFIG_FILE}`);
}

main().catch(console.error);
