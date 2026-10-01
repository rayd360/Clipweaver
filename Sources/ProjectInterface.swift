import AppKit

extension Studio {
    func refreshProjects() {projects=library.entries()}
    func askName(_ title:String,value:String) -> String? {
        let alert=NSAlert();alert.messageText=title;alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel")
        let field=NSTextField(string:value);field.frame=NSRect(x:0,y:0,width:340,height:26);alert.accessoryView=field;alert.window.initialFirstResponder=field
        guard alert.runModal() == .alertFirstButtonReturn else {return nil};return field.stringValue
    }
    func renameProject(_ entry:ProjectEntry) {
        guard !busy,let name=askName("Rename project",value:entry.project.name) else {return}
        do {let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !trimmed.isEmpty,trimmed.count<=100 else {throw WeaverError("Use a name of 1–100 characters.")};var p=entry.project;p.name=trimmed;try p.save(entry.root);if root?.standardizedFileURL.path==entry.root.standardizedFileURL.path {project=p};refreshProjects()} catch {self.error=error.localizedDescription}
    }
    func forgetProject(_ entry:ProjectEntry) {guard !busy else{return};do{try library.forget(entry.root);if root?.standardizedFileURL.path==entry.root.standardizedFileURL.path {project=nil;root=nil;plan=nil;UserDefaults.standard.removeObject(forKey:"lastProject")};refreshProjects()}catch{self.error=error.localizedDescription}}
    func trashProject(_ entry:ProjectEntry) {
        guard !busy else{return}
        if entry.needsDeletionConfirmation {let a=NSAlert();a.messageText="Move “\(entry.project.name)” to Trash?";a.informativeText="This moves the project's review copies, edits, music, overlays and exports to Trash. Original videos referenced outside the project stay in place.";a.addButton(withTitle:"Cancel");a.addButton(withTitle:"Move to Trash")
        guard a.runModal() == .alertSecondButtonReturn else{return}}
        do{try library.trash(entry);status="Project and its contents moved to Trash";if root?.standardizedFileURL.path==entry.root.standardizedFileURL.path {project=nil;root=nil;plan=nil;UserDefaults.standard.removeObject(forKey:"lastProject")};refreshProjects()}catch{self.error=error.localizedDescription}
    }
    func clearCaches(_ entry:ProjectEntry) {
        guard !busy else{return};let a=NSAlert();a.messageText="Clear rebuildable files?";a.informativeText="Review copies, the upload ZIP, and previews will move to Trash. Edits, music, overlays, exports, and originals will remain.";a.addButton(withTitle:"Cancel");a.addButton(withTitle:"Clear")
        guard a.runModal() == .alertSecondButtonReturn else{return}
        do {for n in ["For AI","Upload to AI.zip","Previews"] {let u=entry.root.appendingPathComponent(n);if fm.fileExists(atPath:u.path) {
                let prefix=u.resolvingSymlinksInPath().path+"/"
                guard !entry.project.sources.contains(where:{let path=URL(fileURLWithPath:$0.originalPath).resolvingSymlinksInPath().path;return path==u.resolvingSymlinksInPath().path || path.hasPrefix(prefix)}) else {throw WeaverError("A referenced original is inside this folder. Relink it outside the cache before clearing it.")}
                try fm.trashItem(at:u,resultingItemURL:nil)}};status="Rebuildable files cleared"}catch{self.error=error.localizedDescription}
    }
    func refreshRevisions() {
        guard let root else {revisions=[];return}
        let directory=root.appendingPathComponent("Edits")
        let files=(fm.enumerator(at:directory,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles)?.allObjects as? [URL]) ?? []
        revisions=files.filter{$0.pathExtension=="json"}.sorted{((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)>((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}
    }
    func revisionLabel(_ url:URL) -> String {let name=(try? EditPlan.load(url).title) ?? url.lastPathComponent;let date=(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast;return "\(name) · \(date.formatted(date:.abbreviated,time:.shortened))"}
    func restoreRevision(_ url:URL) {
        guard !busy, var p=project,let root else{return}
        do {let e=try EditPlan.load(url);try e.validate(p);p.lastEditPath=relativeProjectPath(url,root:root)
            if !(p.editChoices ?? []).contains(p.lastEditPath!) {
                let folder=url.deletingLastPathComponent(),responseURL=folder.appendingPathComponent("response.clipweaveredit")
                if let response=try? AIResponse.load(responseURL) {p.editChoices=response.allEdits.indices.map {relativeProjectPath(folder.appendingPathComponent($0==0 ? "edit.json":"edit-\($0+1).json"),root:root)}}else{p.editChoices=[p.lastEditPath!]}
            }
            if let m=e.music {let bundled=url.deletingLastPathComponent().appendingPathComponent(m.filename);if fm.fileExists(atPath:bundled.path) {p.musicPath=relativeProjectPath(bundled,root:root)}} else {p.musicPath=nil}
            project=p;plan=e;try save();status="Earlier edit restored";page=1
        }catch{self.error=error.localizedDescription}
    }
    func chooseResponse() {checkCurrentIncoming(pickerIfEmpty:true)}
    func responsePicker() {let p=NSOpenPanel();p.title="Open ClipWeaver AI response";p.allowsMultipleSelection=false;guard p.runModal() == .OK,let u=p.url else{return};receiveResponse(u)}
    func reviewEdit() {showingProjects=false;page=1;checkCurrentIncoming(pickerIfEmpty:false)}
    func checkCurrentIncoming(pickerIfEmpty:Bool) {
        guard !busy else{return}
        guard let p=project,let r=root else {if pickerIfEmpty {responsePicker()};return}
        run({job,report -> (Project?,EditPlan?,URL?) in
            report("Checking this project's Incoming folder",0.1)
            guard let found=try self.engine.findIncoming(project:p,root:r,job:job) else{return(nil,nil,nil)}
            if found.imported {return(nil,nil,found.editURL)}
            let (updated,edit)=try self.engine.importResponse(found.url,project:p,root:r,job:job)
            return(updated,edit,nil)
        },finish:{updated,edit,existing in
            if let updated,let edit {self.project=updated;self.plan=edit;self.lastOutput=nil;try self.save();self.status="AI choices imported";self.renderChoices()}
            else if let existing {if self.plan==nil {self.restoreRevision(existing)};self.status="Latest response is already in this project's edit history"}
            else if pickerIfEmpty {self.responsePicker();return}
            else {self.status="No new AI response in Incoming"}
            self.showingProjects=false;self.page=1
        })
    }
    func receiveResponse(_ url:URL) {
        guard !busy else{return}
        let known=library.entries();let active=project;let activeRoot=root
        run({job,report in
            report("Opening AI response",0.1)
            let response=try AIResponse.load(url)
            let match: (Project,URL)
            if let p=active,let r=activeRoot,p.projectId==response.edit.projectId {match=(p,r)}
            else if let entry=known.first(where:{$0.project.projectId==response.edit.projectId}) {match=(entry.project,entry.root)}
            else {throw WeaverError("The matching project isn't in your library. Open its Project.clipweaver file once, then open this response again.")}
            let (p,e)=try self.engine.importResponse(url,project:match.0,root:match.1,job:job)
            return (p,match.1,e)
        },finish:{p,r,e in self.project=p;self.root=r;self.plan=e;self.lastOutput=nil;self.showingProjects=false;self.page=1;try self.save();self.status="AI choices saved together";self.renderChoices()})
    }
    func scanIncoming() {
        guard !busy,let p=project,let root else{return}
        let inbox=root.appendingPathComponent("Incoming")
        let urls=((try? fm.contentsOfDirectory(at:inbox,includingPropertiesForKeys:[.contentModificationDateKey,.fileSizeKey],options:.skipsHiddenFiles)) ?? []).filter{$0.pathExtension.lowercased()=="clipweaveredit"}
        for u in urls {
            guard let values=try? u.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey]) else{continue}
            let stamp="\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            if inboxSeen[u.path]==stamp {continue}
            if inboxStable[u.path] != stamp {inboxStable[u.path]=stamp;continue}
            inboxSeen[u.path]=stamp
            if let hash=try? fingerprint(u,job:JobControl()),fm.fileExists(atPath:root.appendingPathComponent("Edits/\(hash.prefix(20))/edit.json").path) {continue}
            // Check only the active project's inbox; do not switch to another project in the background.
            guard let response=try? AIResponse.load(u),response.edit.projectId==p.projectId else {error="Incoming response is damaged, incomplete, or belongs to a different project: \(u.lastPathComponent). The current edit is unchanged.";return}
            checkCurrentIncoming(pickerIfEmpty:false);return
        }
    }
}
