//
//  EPUBParser.swift
//  EPUBKit
//
//  Created by Witek on 09/06/2017.
//  Copyright © 2017 Witek Bobrowski. All rights reserved.
//

import Zip
import AEXML
import Foundation

public final class EPUBParser: EPUBParserProtocol {

    public weak var delegate: EPUBParserDelegate?

    public func parse(documentAt path: URL) throws -> EPUBDocument {
        do {
            delegate?.parser(self, didBeginParsingDocumentAt: path)

            let directory = try unzip(archiveAt: path)
            delegate?.parser(self, didUnzipArchiveTo: directory)

            let contentPath = try getContentPath(from: directory)
            let contentDirectory = contentPath.deletingLastPathComponent()
            let content = try AEXMLDocument(xml: try Data(contentsOf: contentPath))

            let metadata = getMetadata(from: content.root["metadata"])
            delegate?.parser(self, didFinishParsing: metadata)

            let manifest = getManifest(from: content.root["manifest"])
            delegate?.parser(self, didFinishParsing: manifest)

            let spine =  getSpine(from: content.root["spine"])
            delegate?.parser(self, didFinishParsing: spine)

            let tocPathComponent = try manifest.path(forItemWithId: spine.toc ?? "")
            let tocPath = contentDirectory.appendingPathComponent(tocPathComponent)
            let tocData = try Data(contentsOf: tocPath)
            let tocContent = try AEXMLDocument(xml: tocData)
            let tableOfContents = getTableOfContents(from: tocContent.root)
            delegate?.parser(self, didFinishParsing: tableOfContents)

            delegate?.parser(self, didFinishParsingDocumentAt: path)
            return EPUBDocument(directory: directory,
                                contentDirectory: contentDirectory,
                                metadata: metadata,
                                manifest: manifest,
                                spine: spine,
                                tableOfContents: tableOfContents)
        } catch let error {
            delegate?.parser(self, didFailParsingDocumentAt: path, with: error)
            throw error
        }
    }

}

// MARK: - EPUBParsable
extension EPUBParser: EPUBParsable {

    func unzip(archiveAt path: URL) throws -> URL {
        Zip.addCustomFileExtension("epub")
        do {
            return try Zip.quickUnzipFile(path)
        } catch {
            throw EPUBParserError.unZipError
        }
    }

    func getContentPath(from documentPath: URL) throws -> URL {
        do {
            let path = documentPath.appendingPathComponent("META-INF/container.xml")
            let data = try Data(contentsOf: path)
            let container = try AEXMLDocument(xml: data)
            let content = container.root["rootfiles"]["rootfile"].attributes["full-path"]
            return documentPath.appendingPathComponent(content!)
        } catch {
            throw EPUBParserError.containerParseError
        }
    }

    func getMetadata(from xmlElement: AEXMLElement) -> EPUBMetadata {
        var metadata = EPUBMetadata()
        metadata.contributor = Creator(name: xmlElement["dc:contributor"].value,
                                       role: xmlElement["dc:contributor"].attributes["opf:role"],
                                       fileAs: xmlElement["dc:contributor"].attributes["opf:file-as"])
        metadata.coverage = xmlElement["dc:coverage"].value
        metadata.creator = Creator(name: xmlElement["dc:creator"].value,
                                   role: xmlElement["dc:creator"].attributes["opf:role"],
                                   fileAs: xmlElement["dc:creator"].attributes["opf:file-as"])
        metadata.date = xmlElement["dc:date"].value
        metadata.description = xmlElement["dc:description"].value
        metadata.format = xmlElement["dc:format"].value
        metadata.identifier = xmlElement["dc:identifier"].value
        metadata.language = xmlElement["dc:language"].value
        metadata.publisher = xmlElement["dc:publisher"].value
        metadata.relation = xmlElement["dc:relation"].value
        metadata.rights = xmlElement["dc:rights"].value
        metadata.source = xmlElement["dc:source"].value
        metadata.subject = xmlElement["dc:subject"].value
        metadata.title = xmlElement["dc:title"].value
        metadata.type = xmlElement["dc:type"].value
        for metaItem in xmlElement["meta"].all ?? [] where metaItem.attributes["name"] == "cover" {
            metadata.coverId = metaItem.attributes["content"]
        }
        return metadata
    }

    func getManifest(from xmlElement: AEXMLElement) -> EPUBManifest {
        var items: [String: EPUBManifestItem] = [:]
        for item in xmlElement["item"].all! {
            let id = item.attributes["id"]!
            let path = item.attributes["href"]!
            let mediaType = item.attributes["media-type"]
            let properties = item.attributes["properties"]
            items[id] = EPUBManifestItem(id: id,
                                         path: path,
                                         mediaType: EPUBMediaType(rawValue: mediaType!) ?? .unknown,
                                         property: properties)
        }
        return EPUBManifest(id: xmlElement["id"].value, items: items)
    }

    func getSpine(from xmlElement: AEXMLElement) -> EPUBSpine {
        var items: [EPUBSpineItem] = []
        for item in xmlElement["itemref"].all! {
            let id = item.attributes["id"]
            let idref = item.attributes["idref"]!
            let linear = (item.attributes["linear"] ?? "yes") == "yes" ? true : false
            items.append(EPUBSpineItem(id: id, idref: idref, linear: linear))
        }
        let pageProgressionDirection = xmlElement["page-progression-direction"].value ?? "ltr"
        return EPUBSpine(id: xmlElement.attributes["id"],
                         toc: xmlElement.attributes["toc"],
                         pageProgressionDirection: EPUBPageProgressionDirection(
                            rawValue: pageProgressionDirection),
                         items: items)
    }

    func getTableOfContents(from xmlElement: AEXMLElement) -> EPUBTableOfContents {
        let item = xmlElement["head"]["meta"].all(
            withAttributes: ["name": "dtb=uid"])?.first?.attributes["content"]
        var tableOfContents = EPUBTableOfContents(label: xmlElement["docTitle"]["text"].value!,
                                                  id: "0",
                                                  item: item, subTable: [])

        func evaluateChildren(from xmlElement: AEXMLElement) -> [EPUBTableOfContents] {
            if xmlElement["navPoint"].all != nil {
                var subs: [EPUBTableOfContents] = []
                for point in xmlElement["navPoint"].all! {
                    subs.append(EPUBTableOfContents(label: point["navLabel"]["text"].value!,
                                                    id: point.attributes["id"]!,
                                                    item: point["content"].attributes["src"]!,
                                                    subTable: evaluateChildren(from: point)))
                }
                return subs
            } else {
                return []
            }
        }
        tableOfContents.subTable = evaluateChildren(from: xmlElement["navMap"])
        return tableOfContents
    }

}
