import java.time.*
import java.time.temporal.*
import java.nio.file.*
import java.nio.file.attribute.*
import static groovy.io.FileType.*
import static groovy.io.FileVisitResult.*

println "\nStarting script"

if(args.length == 4) {
    int daysToLeft = Integer.valueOf(args[1])
    int dayOfWeekToLeftBefore = Integer.valueOf(args[2])
    int deleteFilesBeforeDays = Integer.valueOf(args[3])
    def now = Instant.now()

    def root = new File(args[0])

    def filesToDelete = []

    root.eachFile(FILES) {
        if(it.name.startsWith("backup") && it.name.endsWith(".tar")) {
            def attr = Files.readAttributes(it.toPath(), BasicFileAttributes.class)
            def creationDate = attr.creationTime().toInstant()
            if(creationDate.isBefore(now.minus(daysToLeft, ChronoUnit.DAYS))) {
                if(creationDate.isBefore(now.minus(deleteFilesBeforeDays, ChronoUnit.DAYS)) ||
                    creationDate.atZone(ZoneId.systemDefault()).getDayOfWeek().getValue() != dayOfWeekToLeftBefore) {
                    filesToDelete.add(it)
                }
            }
        }
    }

    filesToDelete.each {
        if(it.delete()) {
            println it.toString() + " deleted successfully"   
        } else {
            println it.toString() + " failed to delete"
        } 
    }

    println "Script executed successfully"
} else {
    println "\nIllegal argument number. You need to enter 4 arguments."
    println "1) Folder to check"
    println "2) Number of days to left"
    println "3) Number of day to left before 2)"
    println "4) After days to delete in any case"

}
