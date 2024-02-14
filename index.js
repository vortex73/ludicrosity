import fs from 'fs'
import path, { dirname } from 'path'
import matter from 'gray-matter'
import {mkdirp} from 'mkdirp'
import {glob} from 'glob'
import {marked} from 'marked'
const data = (handle)=> {
    const readData = fs.readFileSync(handle,'utf8');
    const header = matter(readData);
    const htmlData = marked(header.content);
    return {...header,htmlData};
}

const convert = (source , {title,date,body})=>
    source
    .replace(/<!--DATE-->/g, date)
    .replace(/<!--TITLE-->/g, title)
    .replace(/<!--BODY-->/g, body);

const add = (fileHandle,contents)=>{
    const dir = dirname(fileHandle)
    try{
    mkdirp.sync(dir)
    fs.writeFileSync(fileHandle, contents)
    }
    catch(err){
        console.log(contents)
        console.error("HELLO ",err)
    }
}

const filePath = (fp,dirr)=>{
    const fn = path.basename(fp)
    const newname = fn.substring(0,fn.length-3)+'.html'
    const outFil = path.join(dirr, newname)
    return outFil
}

const template = fs.readFileSync(
    path.join(path.resolve(),"src/template.html"),
    'utf8'
)

const tempDir = path.join(path.resolve(),"./md")
const outDir = path.join(path.resolve(),"pages")
const integrated = (mdfile,template,outDir)=>{
    const source = data(mdfile)
    const names = filePath(mdfile,outDir)
    const templatified = convert(template,{
        date: source.data.date,
        title: source.data.title,
        body: source.htmlData,
    })
    add(names,templatified)

}
const filenames = glob.sync(tempDir+'**/*.md')
filenames.forEach((x)=>{
    integrated(x,template,outDir)
})
