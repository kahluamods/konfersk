<?xml version="1.0" encoding="ISO-8859-1" ?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns="http://www.w3.org/1999/xhtml">
<xsl:output method="html"/>

<xsl:key name="class-key" match="ksk/classes/c" use="@id"/>
<xsl:key name="user-key" match="ksk/users/u" use="@id"/>
<xsl:key name="qual-key" match="ksk/quals/q" use="@id"/>
<xsl:key name="how-key" match="ksk/lists/l" use="@id"/>
<xsl:key name="item-key" match="ksk/items/i" use="@id"/>

<xsl:template match="/">
<html>
<head>
<meta http-equiv="content-type" content="text/html; charset=iso-8859-1" />
<meta http-equiv="Pragma" content="no-cache" />
<meta http-equiv="Expires" content="-1" />
<title>Current KSK List Positions</title>
<style type="text/css" media="screen">
body {
  margin:0 auto;
  width: 100%;
  color: #ffffff;
  background-color: #000000;
}

h1 {
  color: #edb023;
  font-family:'Lucida Grande','Lucida Sans Unicode',Verdana,sans-serif;
  font-size:16pt;
}

.listname {
  color: #edb023;
  font-family:'Lucida Grande','Lucida Sans Unicode',Verdana,sans-serif;
  font-size:12pt;
}

.poor {
  color:#9d9d9d;
}

.common {
  color:#ffffff;
}

.uncommon {
  color:#1eff00;
}

.rare {
  color:#0070dd;
}

.epic {
  color:#a335ee;
}

.legendary {
  color:#ff8000;
}

.artifact {
  color:#e6cc80;
}

.mage {
  color:#68ccef;
}

.warlock {
  color:#9382c9;
}

.shaman {
  color:#2359ff;
}

.deathknight {
  color:#c41e3a;
}

.priest {
  color:#ffffff;
}

.rogue {
  color:#fff468;
}

.paladin {
  color:#f48cba;
}

.hunter {
  color:#aad372;
}

.druid {
  color:#ff7c0a;
}

.warrior {
  color:#c69b6d;
}

.monk {
  color:#00fe95;
}

.demonhunter {
  color:#a330c9;
}

.unkclass {
  color:#7f7f7f;
}

</style>
<script type="text/javascript" src="http://static.wowhead.com/widgets/power.js"></script>
</head>
<body>
  <h1>KSK Loot History as of <xsl:value-of select="ksk/@date"/></h1>
  <table id="ksktable" border="1" cellspacing="1" cellpadding="10">
    <tr>
      <th>When</th>
      <th>What</th>
      <th>Who</th>
      <th>How</th>
    </tr>
    <xsl:for-each select="ksk/history/h">
      <tr>
        <td><xsl:value-of select="@d"/> at <xsl:value-of select="@t"/></td>
        <xsl:variable name="itemid" select="./@id"/>
        <xsl:variable name="userid" select="./@u"/>
        <xsl:variable name="uclass" select="key('user-key', $userid)/@c"/>
        <xsl:variable name="classnm" select="key('class-key', $uclass)/@v"/>
        <xsl:variable name="how" select="./@w"/>
        <xsl:variable name="iqual" select="key('item-key', $itemid)/@q"/>
        <xsl:variable name="qualnm" select="key('qual-key', $iqual)/@v"/>
        <td><a href="http://www.wowhead.com/item={@id}"><span class="{$qualnm}">
            <xsl:value-of select="key('item-key', $itemid)/@n"/>
           </span></a></td>
        <td><span class="{$classnm}">
            <xsl:value-of select="key('user-key', $userid)/@n"/>
            </span></td>
        <td><xsl:value-of select="key('how-key', $how)/@n"/></td>
      </tr>
    </xsl:for-each>
  </table>
</body>
</html>
</xsl:template>
</xsl:stylesheet>
