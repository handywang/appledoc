//
//  GBDocSetOutputGenerator.m
//  appledoc
//
//  Created by Tomaz Kragelj on 29.11.10.
//  Copyright 2010 Gentle Bytes. All rights reserved.
//

#import "RegexKitLite.h"
#import "GRMustache.h"
#import "GBStore.h"
#import "GBApplicationSettingsProvider.h"
#import "GBTask.h"
#import "GBDataObjects.h"
#import "GBTemplateHandler.h"
#import "GBDocSetOutputGenerator.h"

@interface GBDocSetOutputGenerator ()

- (BOOL)copyOrMoveSourceFilesToDocuments:(NSError **)error;
- (BOOL)processInfoPlist:(NSError **)error;
- (BOOL)processNodesXml:(NSError **)error;
- (BOOL)processTokensXml:(NSError **)error;
- (BOOL)indexDocSet:(NSError **)error;
- (BOOL)removeTemporaryFiles:(NSError **)error;
- (BOOL)processTokensXmlForObjects:(NSArray *)objects type:(NSString *)type template:(NSString *)template index:(NSUInteger *)index error:(NSError **)error;
- (void)addTokensXmlModelObjectDataForObject:(GBModelBase *)object toData:(NSMutableDictionary *)data;
- (void)addTokensXmlModelObjectDataForPropertySetterAndGetter:(GBModelBase *)property withData:(NSDictionary *)data toArray:(NSMutableArray *)members;
- (void)initializeSimplifiedObjects;
- (NSArray *)simplifiedObjectsFromObjects:(NSArray *)objects value:(NSString *)value index:(NSUInteger *)index;
- (NSString *)tokenIdentifierForObject:(GBModelBase *)object;
-(void) addGetterSetterToMethods:(GBMethodData *)property for:(NSString *)name withReturnResult:(NSArray*)results withTypes:(NSArray *)types withArguments:(NSArray *)arguments withData:(NSDictionary *)data toArray:(NSMutableArray *)members;

@property (retain) NSArray *documents;
@property (retain) NSArray *classes;
@property (retain) NSArray *categories;
@property (retain) NSArray *protocols;
@property (retain) NSArray *constants;
@property (readonly) NSMutableSet *temporaryFiles;

@property (retain) id sectionID; //tmp for class's refid

@end

#pragma mark -

@implementation GBDocSetOutputGenerator

#pragma Generation handling

- (BOOL)generateOutputWithStore:(id)store error:(NSError **)error {
	NSParameterAssert(self.previousGenerator != nil);
	
	// Prepare for run.
	if (![super generateOutputWithStore:store error:error]) return NO;
	[self.temporaryFiles removeAllObjects];
	[self initializeSimplifiedObjects];
	
	// Create documentation set from files generated by previous generator.
	if (![self copyOrMoveSourceFilesToDocuments:error]) return NO;
	if (![self processInfoPlist:error]) return NO;
	if (![self processNodesXml:error]) return NO;
	if (![self processTokensXml:error]) return NO;
	if (![self indexDocSet:error]) return NO;
	if (![self removeTemporaryFiles:error]) return NO;	
	return YES;
}

- (BOOL)copyOrMoveSourceFilesToDocuments:(NSError **)error {
	GBLogInfo(@"Moving HTML files to DocSet bundle...");
	
	// Prepare all paths. Note that we determine the exact subdirectory by searching for documents-template and using it's subdirectory as the guide. If documents template wasn't found, exit.
	NSString *sourceFilesPath = [self.inputUserPath stringByStandardizingPath];
	NSString *documentsPath = [self outputPathToTemplateEndingWith:@"documents-template"];
	if (!documentsPath) {
		if (error) *error = [NSError errorWithCode:GBErrorDocSetDocumentTemplateMissing description:@"Documents template is missing!" reason:@"documents-template file is required to determine location for Documents path in DocSet bundle!"];
		GBLogWarn(@"Failed finding documents-template in '%@'!", self.templateUserPath);
		return NO;
	}
	
	// Copy or move all files generated by previous generator to documents subfolder of docset structure.
	if (![self copyOrMoveItemFromPath:sourceFilesPath toPath:documentsPath error:error]) {
		GBLogWarn(@"Failed moving files from '%@' to '%@'!", self.previousGenerator.outputUserPath, documentsPath);
		return NO;
	}
	return YES;
}

- (BOOL)processInfoPlist:(NSError **)error {
#define addVarUnlessEmpty(var,key) if ([var length] > 0) [vars setObject:var forKey:key]
	GBLogInfo(@"Writing DocSet Info.plist...");
	NSString *templateFilename = @"info-template.plist";
	NSString *templatePath = [self templatePathForTemplateEndingWith:templateFilename];
	if (!templatePath) {
		if (error) *error = [NSError errorWithCode:GBErrorDocSetInfoPlistTemplateMissing description:@"Info.plist template is missing!" reason:@"info-template.plist file is required to specify information about DocSet!"];
		GBLogWarn(@"Failed finding info-template.plist in '%@'!", self.templateUserPath);
		return NO;
	}
		
	// Prepare template variables and replace all placeholders with actual values.
	NSMutableDictionary *vars = [NSMutableDictionary dictionaryWithCapacity:20];
	addVarUnlessEmpty(self.settings.docsetBundleIdentifier, @"bundleIdentifier");
	addVarUnlessEmpty(self.settings.docsetBundleName, @"bundleName");
	addVarUnlessEmpty(self.settings.projectVersion, @"bundleVersion");
	addVarUnlessEmpty(self.settings.docsetCertificateIssuer, @"certificateIssuer");
	addVarUnlessEmpty(self.settings.docsetCertificateSigner, @"certificateSigner");
	addVarUnlessEmpty(self.settings.docsetDescription, @"description");
	addVarUnlessEmpty(self.settings.docsetFallbackURL, @"fallbackURL");
	addVarUnlessEmpty(self.settings.docsetFeedName, @"feedName");
	addVarUnlessEmpty(self.settings.docsetFeedURL, @"feedURL");
    addVarUnlessEmpty(NSStringFromGBPublishedFeedFormats(self.settings.docsetFeedFormats), @"feedFormats");
	addVarUnlessEmpty(self.settings.docsetMinimumXcodeVersion, @"minimumXcodeVersion");
	addVarUnlessEmpty(self.settings.docsetPlatformFamily, @"platformFamily");
	addVarUnlessEmpty(self.settings.docsetPublisherIdentifier, @"publisherIdentifier");
	addVarUnlessEmpty(self.settings.docsetPublisherName, @"publisherName");
	addVarUnlessEmpty(self.settings.docsetCopyrightMessage, @"copyrightMessage");
	addVarUnlessEmpty(self.settings.dashDocsetPlatformFamily, @"dashPlatformFamily");
	
	// Run the template and save the results as Info.plist.
	GBTemplateHandler *handler = [self.templateFiles objectForKey:templatePath];
	NSString *output = [handler renderObject:vars];
	NSString *outputPath = [self outputPathToTemplateEndingWith:templateFilename];
	NSString *filename = [outputPath stringByAppendingPathComponent:@"Info.plist"];
	if (![self writeString:output toFile:[filename stringByStandardizingPath] error:error]) {
		GBLogWarn(@"Failed wrtting Info.plist to '%@'!", filename);
		return NO;
	}
	return YES;
}

- (BOOL)processNodesXml:(NSError **)error {
	GBLogInfo(@"Writing DocSet Nodex.xml file...");
	NSString *templateFilename = @"nodes-template.xml";
	NSString *templatePath = [self templatePathForTemplateEndingWith:templateFilename];
	if (!templatePath) {
		if (error) *error = [NSError errorWithCode:GBErrorDocSetNodesTemplateMissing description:@"Nodes.xml template is missing!" reason:@"nodes-template.xml file is required to specify document structure for DocSet!"];
		GBLogWarn(@"Failed finding nodes-template.xml in '%@'!", self.templateUserPath);
		return NO;
	}
	
	// Prepare the variables for the template.
	NSMutableDictionary *vars = [NSMutableDictionary dictionary];
	[vars setObject:self.settings.projectName forKey:@"projectName"];
	[vars setObject:@"index.html" forKey:@"indexFilename"];
	[vars setObject:[NSNumber numberWithBool:([self.documents count] > 0)] forKey:@"hasDocs"];
	[vars setObject:[NSNumber numberWithBool:([self.classes count] > 0)] forKey:@"hasClasses"];
	[vars setObject:[NSNumber numberWithBool:([self.categories count] > 0)] forKey:@"hasCategories"];
	[vars setObject:[NSNumber numberWithBool:([self.protocols count] > 0)] forKey:@"hasProtocols"];
    [vars setObject:[NSNumber numberWithBool:([self.constants count] > 0)] forKey:@"hasConstants"];
	[vars setObject:self.documents forKey:@"docs"];
	[vars setObject:self.classes forKey:@"classes"];
	[vars setObject:self.categories forKey:@"categories"];
	[vars setObject:self.protocols forKey:@"protocols"];
    [vars setObject:self.constants forKey:@"constants"];
	[vars setObject:self.settings.stringTemplates forKey:@"strings"];
	
	// Run the template and save the results.
	GBTemplateHandler *handler = [self.templateFiles objectForKey:templatePath];
	NSString *output = [handler renderObject:vars];
	NSString *outputPath = [self outputPathToTemplateEndingWith:templateFilename];
	NSString *filename = [outputPath stringByAppendingPathComponent:@"Nodes.xml"];
	[self.temporaryFiles addObject:filename];
	if (![self writeString:output toFile:[filename stringByStandardizingPath] error:error]) {
		GBLogWarn(@"Failed writing Nodes.xml to '%@'!", filename);
		return NO;
	}
	return YES;
}

- (BOOL)processTokensXml:(NSError **)error {
	GBLogInfo(@"Writing DocSet Tokens.xml files...");
	
	// Get the template and prepare single Tokens.xml file for each object.
	NSString *templatePath = [self templatePathForTemplateEndingWith:@"tokens-template.xml"];
	if (!templatePath) {
		GBLogWarn(@"Didn't find tokens-template.xml in '%@', DocSet will not be indexed!", self.templateUserPath);
		return YES;
	}

	// Write each object as a separate token file.
	NSUInteger index = 1;
	if (![self processTokensXmlForObjects:self.documents type:@"doc" template:templatePath index:&index error:error]) return NO;
	if (![self processTokensXmlForObjects:self.classes type:@"cl" template:templatePath index:&index error:error]) return NO;
	if (![self processTokensXmlForObjects:self.categories type:@"cat" template:templatePath index:&index error:error]) return NO;
	if (![self processTokensXmlForObjects:self.protocols type:@"intf" template:templatePath index:&index error:error]) return NO;
    if (![self processTokensXmlForObjects:self.constants type:@"tdef" template:templatePath index:&index error:error]) return NO;
	return YES;
}

- (BOOL)indexDocSet:(NSError **)error {
	GBLogInfo(@"Indexing DocSet...");
	GBTask *task = [GBTask task];
	task.reportIndividualLines = YES;
	NSArray *args = [NSArray arrayWithObjects:@"docsetutil", @"index", [self.outputUserPath stringByStandardizingPath], nil];
	BOOL result = [task runCommand:self.settings.xcrunPath arguments:args block:^(NSString *output, NSString *error) {
		if (output) GBLogDebug(@"> %@", [output stringByTrimmingWhitespaceAndNewLine]);
		if (error) GBLogError(@"!> %@", [error stringByTrimmingWhitespaceAndNewLine]);
	}];
	if (!result) {
		if (self.settings.treatDocSetIndexingErrorsAsFatals) {
			if (error) *error = [NSError errorWithCode:GBErrorDocSetUtilIndexingFailed description:@"docsetutil failed to index the documentation set!" reason:task.lastStandardError];
			return NO;
		} else {
			GBLogWarn(@"docsetutil failed to index the documentation set, continuing with what was indexed...");
		}
	}
	return YES;
}

- (BOOL)removeTemporaryFiles:(NSError **)error {
	// We delete all registered temporary files and clear the list. If there are some problems, we simply log but always return YES - if these files remain, documentation set is still usable, so it's no point of aborting... Note that we keep all intermediate files if user has specified so.
	if (self.settings.keepIntermediateFiles) return YES;
	GBLogInfo(@"Removing temporary DocSet files...");
	NSError *err = nil;
	for (NSString *filename in self.temporaryFiles) {
		GBLogDebug(@"Removing '%@'...", filename);
		if (![self.fileManager removeItemAtPath:[filename stringByStandardizingPath] error:&err]) {
			GBLogNSError(err, @"Failed removing temporary file '%@'!", filename);
		}
	}
	return YES;
}

#pragma mark Helper methods

- (BOOL)processTokensXmlForObjects:(NSArray *)objects type:(NSString *)type template:(NSString *)template index:(NSUInteger *)index error:(NSError **)error {
	// Prepare the output path and template handler then generate file for each object.
	GBTemplateHandler *handler = [self.templateFiles objectForKey:template];
	NSString *templateFilename = [template lastPathComponent];
	NSString *outputPath = [self outputPathToTemplateEndingWith:templateFilename];
	NSUInteger idx = *index;
	for (NSMutableDictionary *simplifiedObjectData in objects) {
		// Get the object's methods provider and prepare the array of all methods.
		GBModelBase *topLevelObject = [simplifiedObjectData objectForKey:@"object"];
		
		
		// Prepare template variables for object. Note that we reuse the ID assigned while creating the data for Nodes.xml.
		NSMutableDictionary *objectData = [NSMutableDictionary dictionaryWithCapacity:2];
		[objectData setObject:[simplifiedObjectData objectForKey:@"id"] forKey:@"refid"];
        // save refid
        _sectionID = [objectData objectForKey:@"refid"];
		[self addTokensXmlModelObjectDataForObject:topLevelObject toData:objectData];
		
		NSMutableDictionary *vars = [NSMutableDictionary dictionary];
        
        // Prepare the list of all members.
        if([topLevelObject respondsToSelector:@selector(methods)])
        {
            GBMethodsProvider *methodsProvider = [topLevelObject valueForKey:@"methods"];
            NSMutableArray *membersData = [NSMutableArray arrayWithCapacity:[methodsProvider.methods count]];
            for (GBMethodData *method in methodsProvider.methods) {
                NSMutableDictionary *data = [NSMutableDictionary dictionaryWithCapacity:4];
                [data setObject:[self.settings htmlReferenceNameForObject:method] forKey:@"anchor"];
                [self addTokensXmlModelObjectDataForObject:method toData:data];
                [self addTokensXmlModelObjectDataForPropertySetterAndGetter:method withData:data toArray:membersData];
                [membersData addObject:data];
                
            }
            
            // Prepare the variables for the template.
            [vars setObject:[simplifiedObjectData objectForKey:@"path"] forKey:@"filePath"];
            [vars setObject:objectData forKey:@"object"];
            [vars setObject:membersData forKey:@"members"];
        }
        
        //if the object is a enum typedef, use this enumerator for the values.
        if([topLevelObject isKindOfClass:[GBTypedefEnumData class]])
        {
            GBEnumConstantProvider *typedefEnum = [topLevelObject valueForKey:@"constants"];
            NSMutableArray *constantsData = [NSMutableArray arrayWithCapacity:[typedefEnum.constants count]];
            for (GBEnumConstantData *constant in typedefEnum.constants) {
                NSMutableDictionary *data = [NSMutableDictionary dictionaryWithCapacity:4];
                [data setObject:[self.settings htmlReferenceNameForObject:constant] forKey:@"anchor"];
                [self addTokensXmlModelObjectDataForObject:constant toData:data];
                [constantsData addObject:data];
            }
            
            // Prepare the variables for the template.
            [vars setObject:[simplifiedObjectData objectForKey:@"path"] forKey:@"filePath"];
            [vars setObject:objectData forKey:@"object"];
            [vars setObject:constantsData forKey:@"members"];
        }
		
		// Run the template and save the results.
		NSString *output = [handler renderObject:vars];
		NSString *indexName = [NSString stringWithFormat:@"Tokens%ld.xml", idx++];
		NSString *filename = [outputPath stringByAppendingPathComponent:indexName];
		[self.temporaryFiles addObject:filename];
		if (![self writeString:output toFile:[filename stringByStandardizingPath] error:error]) {
			GBLogWarn(@"Failed writing tokens file '%@'!", filename);
			*index = idx;
			return NO;
		}
	}
	*index = idx;
	return YES;
}

- (void)addTokensXmlModelObjectDataForObject:(GBModelBase *)object toData:(NSMutableDictionary *)data {
	[data setObject:[self tokenIdentifierForObject:object] forKey:@"identifier"];
	[data setObject:[[object.sourceInfosSortedByName objectAtIndex:0] filename] forKey:@"declaredin"];
	if (object.comment) {
		if (object.comment.hasShortDescription) {
			GBCommentComponentsList *components = [GBCommentComponentsList componentsList];
			[components registerComponent:object.comment.shortDescription];
			[data setObject:components forKey:@"abstract"];
		}
		if ([object.comment.relatedItems.components count] > 0) {
			NSMutableArray *related = [NSMutableArray arrayWithCapacity:[object.comment.relatedItems.components count]];
			for (GBCommentComponent *crossref in object.comment.relatedItems.components) {
				if (crossref.relatedItem) {
					NSString *tokenIdentifier = [self tokenIdentifierForObject:crossref.relatedItem];
					if (tokenIdentifier) [related addObject:tokenIdentifier];
				}
			}
			if ([related count] > 0) {
				[data setObject:[NSNumber numberWithBool:YES] forKey:@"hasRelatedTokens"];
				[data setObject:related forKey:@"relatedTokens"];
			}
		}
	}
	if ([object isKindOfClass:[GBMethodData class]]) {
		GBMethodData *method = (GBMethodData *)object;
		[data setObject:method.formattedComponents forKey:@"formattedComponents"];
        [data setObject:_sectionID forKey:@"refid"];
		if (method.comment) {
			if (method.comment.hasMethodParameters) {
				NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:[method.comment.methodParameters count]];
				for (GBCommentArgument *argument in method.comment.methodParameters) {
					NSMutableDictionary *argData = [NSMutableDictionary dictionaryWithCapacity:2];
					[argData setObject:argument.argumentName forKey:@"name"];
					[argData setObject:argument.argumentDescription forKey:@"abstract"];
					[arguments addObject:argData];
				}
				[data setObject:arguments forKey:@"parameters"];
				[data setObject:[NSNumber numberWithBool:YES] forKey:@"hasParameters"];
			}
			if (method.comment.hasMethodResult) {
				NSDictionary *resultData = [NSDictionary dictionaryWithObject:method.comment.methodResult forKey:@"abstract"];
				[data setObject:resultData forKey:@"returnValue"];
			}
			if (method.comment.hasAvailability) {
				NSDictionary *resultData = [NSDictionary dictionaryWithObject:method.comment.availability forKey:@"abstract"];
				[data setObject:resultData forKey:@"availability"];
			}
		}
	}
}

- (void)addTokensXmlModelObjectDataForPropertySetterAndGetter:(GBModelBase *)method withData:(NSDictionary *)data toArray:(NSMutableArray *)members {
	// For all properties we need to add getters and setters to the doc set.
	if (![method isKindOfClass:[GBMethodData class]]) return;
	GBMethodData *property = (GBMethodData *)method;
	if (!property.isProperty) return;
		
	// Setter: returns void, has an argument of the same type as the property, use property's setterSelector as name and avoid duplication of the colon by trimming it. Copy source infos from property.    
	NSArray *setterResults = [NSArray arrayWithObjects:@"void", nil];
	NSArray *setterTypes = [property methodResultTypes];
	NSString *setterName = [property propertySetterSelector];
    setterName = [setterName stringByTrimmingCharactersInSet:[NSCharacterSet punctuationCharacterSet]];
    NSArray *setterArgs = [NSArray arrayWithObject:[GBMethodArgument methodArgumentWithName:setterName types:setterTypes var:@"val"]];
    [self addGetterSetterToMethods:property for:setterName withReturnResult:setterResults withTypes:setterTypes withArguments:setterArgs withData:data toArray:members];
    
    // Getter: returns the same as property, use property's getterSelector as name, takes no arguments. Copy source infos from property.
    NSArray *getterResults = [NSArray arrayWithObjects:property.methodReturnType, nil];
    NSArray *getterTypes = [property methodResultTypes];
    NSString *getterName = [property propertyGetterSelector];
    NSArray *getterArgs = [NSArray arrayWithObject:[GBMethodArgument methodArgumentWithName:getterName types:getterTypes var:nil]];
    [self addGetterSetterToMethods:property for:getterName withReturnResult:getterResults withTypes:getterTypes withArguments:getterArgs withData:data toArray:members];
}

-(void) addGetterSetterToMethods:(GBMethodData *)property
                       for:(NSString *)name
          withReturnResult:(NSArray*)results
                 withTypes:(NSArray *)types
             withArguments:(NSArray *)arguments
               withData:(NSDictionary *)data
                toArray:(NSMutableArray *)members
{
    GBMethodData *method = [GBMethodData methodDataWithType:GBMethodTypeInstance result:results arguments:arguments];
    method.parentObject = property.parentObject;
    method.comment = property.comment;
    for (GBSourceInfo *info in property.sourceInfos) {
        [method registerSourceInfo:info];
    }
    NSMutableDictionary *methodData = [NSMutableDictionary dictionaryWithCapacity:4];
    [methodData setObject:[self.settings htmlReferenceNameForObject:property] forKey:@"anchor"];
    [self addTokensXmlModelObjectDataForObject:method toData:methodData];
    [methodData setObject:[data objectForKey:@"formattedComponents"] forKey:@"formattedComponents"];
    [members addObject:methodData];
    
}

- (NSString *)tokenIdentifierForObject:(GBModelBase *)object {
	if (object.isTopLevelObject) {
		// Class, category and protocol have different prefix, but are straighforward. Note that category has it's class name specified for object name!
		if ([object isKindOfClass:[GBClassData class]]) {
			NSString *objectName = [(GBClassData *)object nameOfClass];
			return [NSString stringWithFormat:@"//apple_ref/occ/cl/%@", objectName];
		} else if ([object isKindOfClass:[GBCategoryData class]]) {
			NSString *objectName = [(GBCategoryData *)object idOfCategory];
			return [NSString stringWithFormat:@"//apple_ref/occ/cat/%@", objectName];
		} else if ([object isKindOfClass:[GBProtocolData class]]){
			NSString *objectName = [(GBProtocolData *)object nameOfProtocol];
			return [NSString stringWithFormat:@"//apple_ref/occ/intf/%@", objectName];
		}
        else if ([object isKindOfClass:[GBTypedefEnumData class]]){
			NSString *objectName = [(GBTypedefEnumData *)object nameOfEnum];
			return [NSString stringWithFormat:@"//apple_ref/occ/tdef/%@", objectName];
		}
	} else if ([object isKindOfClass:[GBDocumentData class]]){
        NSString *objectName = [(GBDocumentData *)object prettyNameOfDocument];
        return [NSString stringWithFormat:@"//apple_ref/occ/doc/%@", objectName];
    } else if ([object isKindOfClass:[GBEnumConstantData class]]){
        NSString *objectName = [(GBEnumConstantData *)object name];
        return [NSString stringWithFormat:@"//apple_ref/occ/tag/%@", objectName];
    } else if (!object.isStaticDocument) {
		// Members are slighly more complex - their identifier is different regarding to whether they are part of class or category/protocol. Then it depends on whether they are method or property. Finally their parent object (class/category/protocol) name (again class name for category) and selector should be added.
		if (!object.parentObject) [NSException raise:@"Can't create token identifier for %@; object is not top level and has no parent assigned!", object];
		
		// First handle parent related stuff.
		GBModelBase *parent = object.parentObject;
		NSString *objectName = nil;
		NSString *objectID = nil;
		if ([parent isKindOfClass:[GBClassData class]]) {
			objectName = [(GBClassData *)parent nameOfClass];
			objectID = ([(GBMethodData *)object methodType] == GBMethodTypeClass) ? @"cl" : @"inst";
		} else if ([parent isKindOfClass:[GBCategoryData class]]) {
			objectName = [(GBCategoryData *)parent nameOfClass];
			objectID = @"inst";
		} else {
			objectName = [(GBProtocolData *)parent nameOfProtocol];
			objectID = @"intf";
		}
		
		// Prepare the actual identifier based on method type.
		GBMethodData *method = (GBMethodData *)object;
		if (method.methodType == GBMethodTypeProperty)
			return [NSString stringWithFormat:@"//apple_ref/occ/%@p/%@/%@", objectID, objectName, method.methodSelector];
		else
			return [NSString stringWithFormat:@"//apple_ref/occ/%@m/%@/%@", objectID, objectName, method.methodSelector];
	}
	return nil;
}

- (void)initializeSimplifiedObjects {
	// Prepare flat list of objects for library nodes.
	GBLogDebug(@"Initializing simplified object representations...");
	NSUInteger index = 1;
	self.documents = [self simplifiedObjectsFromObjects:[self.store documentsSortedByName] value:@"prettyNameOfDocument" index:&index];
	self.classes = [self simplifiedObjectsFromObjects:[self.store classesSortedByName] value:@"nameOfClass" index:&index];
	self.categories = [self simplifiedObjectsFromObjects:[self.store categoriesSortedByName] value:@"idOfCategory" index:&index];
	self.protocols = [self simplifiedObjectsFromObjects:[self.store protocolsSortedByName] value:@"nameOfProtocol" index:&index];
    self.constants = [self simplifiedObjectsFromObjects:[self.store constantsSortedByName] value:@"nameOfEnum" index:&index];
}

- (NSArray *)simplifiedObjectsFromObjects:(NSArray *)objects value:(NSString *)value index:(NSUInteger *)index {
	NSUInteger idx = *index;
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[objects count]];
	for (id object in objects) {
		GBLogDebug(@"Initializing simplified representation of %@ with id %ld...", object, idx);
		NSMutableDictionary *data = [NSMutableDictionary dictionaryWithCapacity:4];
		[data setObject:object forKey:@"object"];
		[data setObject:[NSString stringWithFormat:@"%ld", idx++] forKey:@"id"];
		[data setObject:[object valueForKey:value] forKey:@"name"];
		[data setObject:[self.settings htmlReferenceForObjectFromIndex:object] forKey:@"path"];
		[result addObject:data];
	}
	*index = idx;
	return result;
}

#pragma mark Overriden methods

- (NSString *)outputSubpath {
	return @"docset";
}

#pragma mark Properties

- (NSString *)docsetInstallationPath {
	return [self.settings.docsetInstallPath stringByAppendingPathComponent:self.settings.docsetBundleFilename];
}

- (NSMutableSet *)temporaryFiles {
	static NSMutableSet *result = nil;
	if (!result) result = [[NSMutableSet alloc] init];
	return result;
}

@synthesize documents;
@synthesize classes;
@synthesize categories;
@synthesize protocols;
@synthesize constants;

@end
