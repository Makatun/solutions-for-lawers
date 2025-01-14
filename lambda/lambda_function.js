const cheerio = require('cheerio');

exports.handler = async (event) => {
    console.log("Hello World");

    // Example usage of cheerio
    const html = '<h2 class="title">Hello world2222</h2>';
    const $ = cheerio.load(html);
    console.log($('h2.title').text()); // prints "Hello world"
};