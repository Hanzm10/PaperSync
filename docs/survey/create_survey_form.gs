/**
 * Creates the PaperSync User Evaluation form and a response sheet that
 * computes each statement's mean and interpretation (Tables 7 and 8).
 * Run createPaperSyncSurvey once at script.google.com.
 */
const DOCS_FOLDER_ID = '1_hWkE3Yribq2vakK9ZyM5rsQhCyJK-dF';

const STATEMENTS = [
  'The system is easy to set up and use.',
  'The writing on the phone matches what I wrote on paper.',
  'The ink appears on the phone without a noticeable delay.',
  'The tablet and stylus buttons are convenient to use.',
  'Searching my handwriting helps me find my notes.',
  'I would use PaperSync for my own notes.',
];

function createPaperSyncSurvey() {
  const form = FormApp.create('PaperSync User Evaluation');
  form.setDescription(
    'Thank you for trying PaperSync. Please write on the notebook with the ' +
    'PaperSync stylus for a few minutes, use the tablet and stylus buttons, ' +
    'and try searching for a word you wrote. Then rate each statement from ' +
    '1 to 5, where 5 means strongly agree and 1 means strongly disagree.');
  form.setCollectEmail(false);
  form.setProgressBar(true);
  form.setConfirmationMessage('Thank you for evaluating PaperSync!');

  form.addSectionHeaderItem().setTitle('Part 1. Respondent information');
  form.addTextItem().setTitle('Name (optional)').setRequired(false);
  form.addMultipleChoiceItem()
    .setTitle('Role')
    .setChoiceValues(['Student', 'Teacher', 'Professional'])
    .showOtherOption(true)
    .setRequired(true);
  form.addMultipleChoiceItem()
    .setTitle('How often do you take handwritten notes?')
    .setChoiceValues(['Daily', 'Weekly', 'Rarely'])
    .setRequired(true);

  form.addSectionHeaderItem().setTitle('Part 2. Evaluation');
  STATEMENTS.forEach(function (statement, i) {
    form.addScaleItem()
      .setTitle((i + 1) + '. ' + statement)
      .setBounds(1, 5)
      .setLabels('Strongly disagree', 'Strongly agree')
      .setRequired(true);
  });

  form.addSectionHeaderItem().setTitle('Part 3. Comments');
  form.addParagraphTextItem()
    .setTitle('What did you like most about PaperSync?').setRequired(false);
  form.addParagraphTextItem()
    .setTitle('What should be improved?').setRequired(false);

  // Responses go to a sheet with a Summary tab for Table 7.
  const ss = SpreadsheetApp.create('PaperSync User Evaluation (Responses)');
  form.setDestination(FormApp.DestinationType.SPREADSHEET, ss.getId());
  SpreadsheetApp.flush();
  const responses = ss.getSheets().filter(function (s) {
    return s.getFormUrl();
  })[0];
  const src = "'" + (responses ? responses.getName() : 'Form Responses 1') + "'";

  const summary = ss.insertSheet('Summary');
  summary.getRange('A1:C1').setValues([['Statement', 'Mean', 'Interpretation']])
    .setFontWeight('bold');
  // Columns: A timestamp, B name, C role, D frequency, E to J the ratings.
  // Whole columns, because each response is inserted as a new row and a
  // reference like E2:E would shift down past the data.
  const columns = ['E', 'F', 'G', 'H', 'I', 'J'];
  STATEMENTS.forEach(function (statement, i) {
    const row = i + 2;
    const col = columns[i];
    summary.getRange('A' + row).setValue(statement);
    summary.getRange('B' + row).setFormula(
      '=IFERROR(ROUND(AVERAGE(' + src + '!' + col + ':' + col + '),2),"")');
    summary.getRange('C' + row).setFormula(interpretation('B' + row));
  });
  summary.getRange('A8').setValue('Overall mean').setFontWeight('bold');
  summary.getRange('B8').setFormula('=IFERROR(ROUND(AVERAGE(B2:B7),2),"")');
  summary.getRange('C8').setFormula(interpretation('B8'));
  summary.getRange('A10').setValue('Respondents (n)').setFontWeight('bold');
  summary.getRange('B10').setFormula('=COUNTA(' + src + '!A:A)-1');
  summary.autoResizeColumns(1, 3);

  // Keep everything in the documentation folder.
  try {
    const folder = DriveApp.getFolderById(DOCS_FOLDER_ID);
    DriveApp.getFileById(form.getId()).moveTo(folder);
    DriveApp.getFileById(ss.getId()).moveTo(folder);
  } catch (e) {
    Logger.log('Could not move the files to the folder: ' + e);
  }

  Logger.log('Share this link with respondents: ' + form.getPublishedUrl());
  Logger.log('Edit the form: ' + form.getEditUrl());
  Logger.log('Responses and Summary: ' + ss.getUrl());
}

function interpretation(cell) {
  return '=IF(' + cell + '="","",IF(' + cell + '>=4.21,"Strongly agree",IF(' +
    cell + '>=3.41,"Agree",IF(' + cell + '>=2.61,"Neutral",IF(' + cell +
    '>=1.81,"Disagree","Strongly disagree")))))';
}
