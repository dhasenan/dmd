module dmd.importcache;

import dmd.root.array;
import dmd.root.filename;
import dmd.root.rmem;
version (Posix) import core.sys.posix.dirent;

__gshared PotentialImportCache potentialImportCache;

class PotentialImportCache
{
    private const(char)[][] importPaths;
    private Entry[] roots;
    private bool loaded = false;

    void loadEager()
    {
        if (loaded) return;
        import dmd.globals : global;
        import dmd.utils : toDString;
        auto imppath = global.params.imppath;
        if (imppath != null)
        {
            for (size_t i = 0; i < imppath.dim; i++)
            {
                auto p = (*imppath)[i];
                loadRoot(p.toDString);
            }
            loadRoot(".");
        }
        loaded = true;
    }

    private void loadRoot(const(char)[] p)
    {
        auto entry = new Entry;
        entry.type = EntryType.root;
        entry.name = p;
        listRecursive(entry);
        roots ~= entry;
    }

    /** Locate an import directive among configured import directories.
      *
      * This expects a series of package/module parts, like if you have:
      *   import std.experimental.logger.core;
      * this expects ["std", "experimental", "logger", "core"]
      *
      * This does search for package.d appropriately.
      */
    const(char)[] lookup(const(char)[][] parts)
    {
        if (!loaded) loadEager;
        foreach (root; roots)
        {
            auto e = root.locate(parts);
            if (e !is null) return e.fullName;
        }
        return null;
    }

    version (Posix) const(char)[] nameToDString(const ref char[256] name)
    {
        foreach (i, v; name)
        {
            if (v == '\0')
            {
                return name[0..i].idup;
            }
        }
        // We really shouldn't encounter this.
        return name[].idup;
    }

    version (Posix) private void list(Entry dir)
    {
        DIR* p = opendir(dir.fullNamez);
        while (p)
        {
            auto dirent = readdir(p);
            if (dirent is null) break;
            if (dirent.d_name[0] == '.') continue;
            Entry child = new Entry();
            child.parent = dir;
            child.name = nameToDString(dirent.d_name);
            switch (dirent.d_type)
            {
                case DT_DIR:
                    child.type = EntryType.dir;
                    break;
                case DT_REG:
                    auto ext = FileName.ext(child.name);
                    if (ext != "d" && ext != "di" && ext != null)
                    {
                        // This is not a D file.
                        child.destroy;
                        continue;
                    }
                    break;
                case DT_LNK:
                    child.type = trueType(child.fullNamez);
                    if (child.type == EntryType.invalid)
                    {
                        continue;
                    }
                    break;
                default:
                    child.destroy;
                    continue;
            }
            child.name = nameToDString(dirent.d_name);
            dir.children ~= child;
        }
        closedir(p);
    }

    version (Posix) private EntryType trueType(const(char)* path)
    {
        // TODO implement
        return EntryType.invalid;
    }

    private void listRecursive(Entry dir)
    {
        list(dir);
        foreach (child; dir.children)
        {
            if (child.type == EntryType.dir) listRecursive(child);
        }
    }
}

enum EntryType
{
    dir, file, root, invalid,
}

private class Entry
{
    /// The entry's parent.
    Entry parent;

    /** The name of the entry: either an import path passed in, or a name
      * retrieved by filesystem apis. */
    const(char)[] name;

    // Cached full name, null-terminated string.
    private const(char)[] _fullName;

    /// Whether it's a directory, file, or import path root.
    EntryType type = EntryType.file;

    /// Children of this entry.
    Entry[] children;

    /// The base name of the file, sans extension. Lazily created slice of name.
    private const(char)[] _baseName;

    /// The full name as a null-terminated string.
    const(char)* fullNamez() @property
    {
        return fullName.ptr;
    }

    /// The full name as a D string.
    const(char)[] fullName()
    {
        if (_fullName is null)
        {
            size_t length = 0;
            for (Entry p = this; p !is null; p = p.parent)
            {
                // There's a separator between each and a null terminator.
                length += 1;
                length += p.name.length;
            }
            char[] buf = new char[length];
            buf[$-1] = '\0';
            long lastWritten = buf.length;
            for (Entry p = this; p !is null; p = p.parent)
            {
                if (lastWritten == buf.length)
                {
                    lastWritten--;
                    buf[lastWritten] = '\0';
                }
                else
                {
                    lastWritten--;
                    version (Posix)
                        buf[lastWritten] = '/';
                    else
                        buf[lastWritten] = '\\';
                }
                buf[lastWritten - p.name.length .. lastWritten] = p.name[];
                lastWritten -= p.name.length;
            }
            _fullName = buf[0..$-1];
        }
        return _fullName;
    }

    /** Locate an import directive in this subtree.
      *
      * This expects a series of package/module parts, like if you have:
      *   import std.experimental.logger.core;
      * this expects ["std", "experimental", "logger", "core"]
      *
      * This does search for package.d appropriately.
      */
    Entry locate(const char[][] parts)
    {
        final switch (type)
        {
            case EntryType.root:
                foreach (child; children)
                {
                    auto e = child.locate(parts);
                    if (e !is null) return e;
                }
                return null;
            case EntryType.dir:
                if (baseName != parts[0]) return null;
                auto search = parts.length > 1 ? parts[1..$] : justPackageD;
                foreach (child; children)
                {
                    auto e = child.locate(search);
                    if (e !is null) return e;
                }
                return null;
            case EntryType.file:
                if (parts.length == 1 && parts[0] == baseName)
                {
                    return this;
                }
                return null;
            case EntryType.invalid:
                return null;
        }
    }

    private static immutable justPackageD = ["package"];

    private const(char)[] baseName()
    {
        if (_baseName is null)
        {
            _baseName = name;
            for (int i = cast(int)name.length - 1; i >= 0; i--)
            {
                if (name[i] == '.')
                {
                    _baseName = name[0..i];
                    break;
                }
            }
        }
        return _baseName;
    }
}
