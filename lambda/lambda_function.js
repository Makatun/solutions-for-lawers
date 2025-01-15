/* global fetch */
const cheerio = require('cheerio');
const AWS = require('aws-sdk');
const s3 = new AWS.S3();

exports.handler = async (event) => {

    // var scrapeDate = new Date(Date.parse("1/30/2024"));
    const scrapeDate = new Date()
    const scrapedData = await scrapeTable(scrapeDate);

    const latestJson = await grabLatestJsonFromS3();

    console.log("OLD:" + JSON.stringify(latestJson, null, 2))
    console.log("NEW:" + JSON.stringify(scrapedData, null, 2))

    // Compare the latest JSON with the new scrapedData
    if (latestJson !== null && JSON.stringify(scrapedData) === JSON.stringify(latestJson)) {
        console.log('No changes detected');
        return;
    }

    await uploadNewFilesToS3(scrapeDate, scrapedData);
};



async function uploadNewFilesToS3(scrapeDate, scrapedData) {
    const params = {
        Bucket: 'visa-bulleting-s3', // S3 bucket name
        Key: `visa-bulleting-${scrapeDate.toISOString()}.json`, // File name
        Body: JSON.stringify(scrapedData),
        ContentType: 'application/json'
    };

    try {
        await s3.putObject(params).promise();
        await s3.putObject({ ...params, Key: `visa-bulleting-latest.json` }).promise();
        console.log('File uploaded successfully');
    } catch (error) {
        console.error('Error uploading file:', error);
    }
}

async function grabLatestJsonFromS3() {
    try {
        const latestData = await s3.getObject({ Bucket: 'visa-bulleting-s3', Key: 'visa-bulleting-latest.json' }).promise();
        const latestJson = JSON.parse(latestData.Body.toString('utf-8'));
        return latestJson;
    } catch (error) {
        if (error.code === 'NoSuchKey') {
            console.log('File does not exist in the bucket.');
            return null;
        } else {
            throw error;
        }
    }
}


const options = {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
};

async function scrapeTable(currentDate) {
    try {

        console.log(`Scraping visa bulletin for ${currentDate.toLocaleDateString("en-US", options)}`);


        const month = currentDate.getMonth();
        const monthName = currentDate.toLocaleString('default', { month: 'long' }).toLocaleLowerCase();

        let currentYear = currentDate.getFullYear();
        let fiscalYear = currentDate.getFullYear();

        if (month + 1 > 9)
            fiscalYear = fiscalYear + 1; // Fiscal year starts in October

        const url = `https://travel.state.gov/content/travel/en/legal/visa-law0/visa-bulletin/${fiscalYear}/visa-bulletin-for-${monthName}-${currentYear}.html`;
        console.log(url);
        // https://travel.state.gov/content/travel/en/legal/visa-law0/visa-bulletin/2025/visa-bulletin-for-december-2024.html


        const res = await fetch(url)
        if (!res.ok) {
            throw new Error(`Failed to fetch page: ${res.status} ${res.statusText}`);
        }

        const html = await res.text()
        const $ = cheerio.load(html)


        const tables = {};

        $('tbody')
            .filter((index, tbodyObj) => $(tbodyObj).children().length === 6)
            .each((index, tbodyObj) => {

                const table = {};

                // console.log({ ["here " + index]: $(tbodyObj).text() });
                // // Extract rows
                $(tbodyObj).find('tr').each((index, tr) => {

                    // console.log({ ["here " + index]: $(tr).text() });
                    switch (index) {
                        case 0: break; // Skip first row                        
                        case 1: table["F1"] = parseRow($, tr); break;
                        case 2: table["F2A"] = parseRow($, tr); break;
                        case 3: table["F2B"] = parseRow($, tr); break;
                        case 4: table["F3"] = parseRow($, tr); break;
                        case 5: table["F4"] = parseRow($, tr); break;
                        default: throw new Error("More than 5 rows found!");
                    }
                });


                if (index === 0)
                    tables["FINAL ACTION DATES"] = table;
                if (index === 1)
                    tables["DATES FOR FILING"] = table;
                if (index > 1)
                    throw new Error("More than 2 tables with 6 rows found!");
            });

        return tables;

    } catch (error) {
        console.error('Error scraping table:', error);
    }
}

function parseRow($, tr) {
    const rowData = {};

    $(tr).find('td').each((index, td) => {

        // console.log({ ["here " + index]: $(td).text() });
        switch (index) {
            case 0: break; // Skip first row                        
            case 1: rowData["All"] = parseDate($, td); break;
            case 2: rowData["CHINA"] = parseDate($, td); break;
            case 3: rowData["INDIA"] = parseDate($, td); break;
            case 4: rowData["Mexico"] = parseDate($, td); break;
            case 5: rowData["Philippines"] = parseDate($, td); break;
            default: throw new Error("More than 5 columns found!");
        }
    });
    return rowData;
}


function parseDate($, date) {
    return new Date(Date.parse($(date).text().trim())).toLocaleDateString("en-US", options);
}