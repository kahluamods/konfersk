This directory contains two XML stylesheets you can use to format the
data exported by KSK into a user-friendly format. Both places in KSK
that export XML (the list export and the item history export) produce
mostly-well formed XML, but they both lack a full XML header. You need
to prepend something like the following two lines to the output before
you upload it to your website:

    <?xml version="1.0" encoding="ISO-8859-1"?>
    <?xml-stylesheet type="text/xsl" href="NAME.xslt"?>

NAME.xslt is whatever you call the stylesheet files, in case you rename
them from the two below. The two stylesheets provided here are:

  ksklist.xslt - displays the export of the various lists
  kskitems.xslt - displays the loot item history data

Not all browsers can render XML directly, although most modern ones can.
It is well beyond the scope of this document to describe how to set up a
web server to do the rendering on the server side if you want to support
old browsers.
