import fs, { readFile, readFileSync } from "fs"
import path from 'path'
import matter from 'gray-matter'
import marked from 'marked'
const data = (handle)=> {
    const readData = fs.readFileSync(handle,'utf8');
    const header = matter(readData);
    const htmlData = marked(header);
    return {...header,htmlData};
}

const convert = (source , {title,date,body})=>{
    source
    .replace(/<!--DATE-->/, date)
    .replace(/<!--TITLE-->/, title)
    .replace(/<!--BODY-->)/, body);
            
}

const source = readFile(path.join(path.resolve()),'./template.html')
const outFile = readFile(path.join(path.resolve()), './md/test.md' );
