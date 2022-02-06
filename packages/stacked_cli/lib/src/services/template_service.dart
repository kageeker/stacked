import 'dart:async';
import 'dart:io';

import 'package:mustache_template/mustache_template.dart';
// TODO: Refactor into a service so we can mock out the return value
import 'package:path/path.dart' as p;
import 'package:pubspec_yaml/pubspec_yaml.dart';
import 'package:recase/recase.dart';
import 'package:stacked_cli/src/exceptions/invalid_stacked_structure_exception.dart';
import 'package:stacked_cli/src/locator.dart';
import 'package:stacked_cli/src/message_constants.dart';
import 'package:stacked_cli/src/models/template_item.dart';
import 'package:stacked_cli/src/services/file_service.dart';
// import 'package:stacked_cli/src/templates/generic_view_template.dart';
// import 'package:stacked_cli/src/templates/generic_viewmodel_template.dart';
// import 'package:stacked_cli/src/templates/generic_viewmodel_test_template.dart';
import 'package:stacked_cli/src/templates/template.dart';
import 'package:stacked_cli/src/templates/template_constants.dart';
import 'package:stacked_cli/src/templates/template_helper.dart';

Map<String, StackedTemplate> stackdTemplates = {
  'view': StackedTemplate(templateFiles: [
    TemplateFile(
      relativeOutputPath: 'lib/ui/views/generic/generic_view.dart',
      content: 'GenericViewTemplate',
    ),
    TemplateFile(
      relativeOutputPath: 'lib/ui/views/generic/generic_viewmodel.dart',
      content: 'GenericViewModelTemplate',
    ),
    TemplateFile(
      relativeOutputPath: 'test/viewmodel_tests/generic_viewmodel_test.dart',
      content: 'GenericViewModelTestTemplate',
    )
  ], modificationFiles: [
    ModificationFile(
      relativeModificationPath: 'lib/app/app.dart',
      modificationIdentifier: kModificationIdentifierAppRoutes,
      // TODO: add an option to create Cupertino or custom routes
      modificationTemplate: 'MaterialRoute(page: {{viewName}}),',
      modificationProblemError: kInvalidStackedStructureAppFile,
    ),
    ModificationFile(
      relativeModificationPath: 'lib/app/app.dart',
      modificationIdentifier: kModificationIdentifierAppImports,
      // TODO: add an option to create Cupertino or custom routes
      modificationTemplate:
          'import \'package:{{packageName}}/ui/views/{{viewFolderName}}/{{viewFileName}}\';',
      modificationProblemError: kInvalidStackedStructureAppFile,
    ),
  ])
};

/// Given the data that points to templates it writes out those templates
/// using the same file paths
class TemplateService {
  final _fileService = locator<FileService>();

  /// Reads the template folder and creates the dart code that will be used to generate
  /// the templates
  Future<void> compileTemplateInformation() async {
    print('********' + Directory.current.path);
    final templatesPath = p.joinAll([
      Directory.current.path,
      'lib',
      'src',
      'templates',
    ]);
    final allFilesInTemplateDirectory = await _fileService.getFilesInDirectory(
      directoryPath: templatesPath,
    );
    final stackedTemplatePaths = await _fileService.getFoldersInDirectory(
      directoryPath: templatesPath,
    );

    final templateHelper = TemplateHelper();
    // Get the template files only
    final allTemplateFiles = templateHelper.getTemplatesFilesOnly(
      filePaths: allFilesInTemplateDirectory,
    );

    const String templateDataStructure = '''
/// NOTE: This is generated code from the compileTemplates command. Do not modify by hand
///       This file should be checked into source control.

{{#templateItems}}

// -------- {{templateFileName}} Template Data ----------

const String k{{templateName}}Template{{templateFileName}}Path =
    '{{templateFilePath}}';

const String k{{templateName}}Template{{templateFileName}}Content = \'''
{{{templateFileContent}}}
\''';

// --------------------------------------------------

{{/templateItems}}
''';

    final templateItemsToRender = <TemplateItem>[];

    // Loop through each template
    for (final stackedTemplatePath in stackedTemplatePaths) {
      // the actual name of the stacked template
      final stackedTemplate = p.basename(stackedTemplatePath);

      // Get the files for that template from all files
      final templateFiles = templateHelper.getFilesForTemplate(
        filePaths: allTemplateFiles,
        templateName: stackedTemplate,
      );

      final templateNameRecase = ReCase(stackedTemplate);
      final templateFolderName = p.join('templates', 'view');

      for (final templateFile in templateFiles) {
        // TODO: Move into template helper and unit test
        final templateFileNameOnly =
            p.basename(templateFile.path).replaceFirst('.dart.stk', '');

        final templateFileNameRecase = ReCase(templateFileNameOnly);

        // TODO: Move into template helper and unit test
        final relativeTemplateFilePath =
            templateFile.path.split(templateFolderName).last;

        final templateFileContent =
            await _fileService.readFile(filePath: templateFile.path);

        templateItemsToRender.add(TemplateItem(
          templateName: templateNameRecase.pascalCase,
          templateFileName: templateFileNameRecase.pascalCase,
          templateFilePath: relativeTemplateFilePath.replaceAll('\\', '\\\\'),
          templateFileContent: templateFileContent,
        ));
      }

      // All items collected, time to render and write them to disk
      final outputTemplate = Template(templateDataStructure);
      final allTemplateItemsContent = outputTemplate.renderString({
        'templateItems': templateItemsToRender.map((e) => e.toJson()),
      });

      await _fileService.writeFile(
        file: File(p.join(templatesPath, 'compiled_templates.dart')),
        fileContent: allTemplateItemsContent,
      );
    }
  }

  /// Using the [templateName] this function will write out the template
  /// files in the directory the cli is currently running.
  Future<void> renderTemplate({
    required String templateName,

    /// The name to use for the views when generating the view template
    String? viewName,
    bool verbose = false,

    /// When set to true the newly generated view will not be added to the app.dart file
    bool excludeRoute = false,
  }) async {
    if (templateName == 'view') {
      if (viewName == null) {
        throw Exception(
            'When using the view template supplying the viewName parameter is required');
      }
    }

    // Get the template that we want to render
    final template =
        stackdTemplates[templateName] ?? StackedTemplate(templateFiles: []);

    await writeOutTemplateFiles(
      template: template,
      templateName: templateName,
      viewName: viewName,
    );

    if (templateName == 'view' && !excludeRoute) {
      await modifyExistingFiles(
        template: template,
        templateName: templateName,
        viewName: viewName,
      );
    }
  }

  Future<void> writeOutTemplateFiles({
    required StackedTemplate template,
    required String templateName,
    String? viewName,
  }) async {
    for (final templateFile in template.templateFiles) {
      final templateContent = renderContentForTemplate(
        content: templateFile.content,
        templateName: templateName,
        viewName: viewName,
      );

      final templateFileOutputPath = getTemplateOutputPath(
        inputTemplatePath: templateFile.relativeOutputPath,
        viewName: viewName,
      );

      await _fileService.writeFile(
        file: File(templateFileOutputPath),
        fileContent: templateContent,
      );
    }
  }

  /// Returns the output path for the file given the input path of the template
  String getTemplateOutputPath({
    required String inputTemplatePath,
    String? viewName,
  }) {
    // TODO: Remove the duplicate code
    final recaseViewName = ReCase(viewName ?? '');
    return inputTemplatePath.replaceAll(
      'generic',
      recaseViewName.snakeCase,
    );
  }

  /// Takes in a templated string [content] and builds the template data
  /// to use when rendering
  String renderContentForTemplate({
    required String content,
    required String templateName,
    String? viewName,
  }) {
    var viewTemplate = Template(content, lenient: true);

    // This functionality is separate and will have to move into its own place
    // It WILL become a lot more complicated.
    final viewNameRecase = ReCase(viewName ?? '');
    // TODO: Refactor this to get different render data depending on the template
    final renderData = {
      kTemplatePropertyViewName: '${viewNameRecase.pascalCase}View',
      kTemplatePropertyViewModelName: '${viewNameRecase.pascalCase}ViewModel',
      kTemplatePropertyViewModelFileName:
          '${viewNameRecase.snakeCase}_viewmodel.dart',
    };

    return viewTemplate.renderString(renderData);
  }

  Future<void> modifyExistingFiles({
    required StackedTemplate template,
    required String templateName,
    String? viewName,
  }) async {
    for (final fileToModify in template.modificationFiles) {
      final fileExists = await _fileService.fileExists(
        filePath: fileToModify.relativeModificationPath,
      );

      if (!fileExists) {
        throw InvalidStackedStructureException(kInvalidStackedStructureAppFile);
      }

      final fileContent = await _fileService.readFile(
        filePath: fileToModify.relativeModificationPath,
      );

      final updatedFileContent = templateModificationFileContent(
        fileContent: fileContent,
        modificationIdentifier: fileToModify.modificationIdentifier,
        modificationTemplate: fileToModify.modificationTemplate,
        viewName: viewName,
      );

      // Write the file back that was modified
      await _fileService.writeFile(
        file: File(fileToModify.relativeModificationPath),
        fileContent: updatedFileContent,
      );
    }
  }

  String templateModificationFileContent({
    required String fileContent,
    required String modificationTemplate,
    required String modificationIdentifier,
    String? viewName,
  }) {
    final template = Template(
      modificationTemplate,
      lenient: true,
    );

    // TODO: We need to be able to unit test this (will become important if it ever breaks somethings)
    final pubspecYaml = File('pubspec.yaml').readAsStringSync().toPubspecYaml();

    // TODO: Remove duplicate code below
    final viewNameRecase = ReCase(viewName ?? '');
    final renderedTemplate = template.renderString(
      {
        // TODO: Create helper extensions for modifying the viewName passed in
        kTemplatePropertyViewName: '${viewNameRecase.pascalCase}View',
        kTemplatePropertyPackageName: pubspecYaml.name,
        kTemplateViewFolderName: viewNameRecase.snakeCase,
        kTemplateViewFileName: '${viewNameRecase.snakeCase}_view.dart',
      },
    );

    // Take the content, replace the identifier in the file with the new code
    // plus the identifier so we can do the same thing again later.
    return fileContent.replaceFirst(
      modificationIdentifier,
      '$renderedTemplate\n$modificationIdentifier',
    );
  }
}
