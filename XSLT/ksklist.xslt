<?xml version="1.0" encoding="ISO-8859-1" ?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns="http://www.w3.org/1999/xhtml">
<xsl:output method="html"/>

<xsl:key name="class-key" match="ksk/classes/c" use="@id"/>
<xsl:key name="user-key" match="ksk/users/u" use="@id"/>

<xsl:template name="loopusers">
  <xsl:param name="startval"/>
  <xsl:param name="endval"/>

  <xsl:if test="$startval &lt;= $endval">
    <tr>
    <td><xsl:value-of select="$startval"/></td>
    <xsl:for-each select="/ksk/lists/list">
      <xsl:variable name="uid" select="./u[$startval]/@id"/>
      <xsl:variable name="uname" select="key('user-key', $uid)/@n"/>
      <xsl:variable name="uclass" select="key('user-key', $uid)/@c"/>
      <xsl:variable name="classnm" select="key('class-key', $uclass)/@v"/>
      <td><span class="{$classnm}"><xsl:value-of select="$uname"/></span>&#160;</td>
    </xsl:for-each>
    </tr>
    <xsl:call-template name="loopusers">
      <xsl:with-param name="startval" select="$startval + 1"/>
      <xsl:with-param name="endval" select="$endval"/>
    </xsl:call-template>
  </xsl:if>
</xsl:template>

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

.monk {
  color:#00fe95;
}

.warrior {
  color:#c69b6d;
}

.demonhunter {
  color:#a330c9
}

</style>
</head>
<body>
  <h1>Current KSK List Positions as of <xsl:value-of select="ksk/@date"/></h1>
  <xsl:variable name="longest">
    <xsl:for-each select="ksk/lists/list">
      <xsl:sort select="count(./u)" data-type="number"/>
      <xsl:if test="position()=last()">
        <xsl:value-of select="count(./u)"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>
  <table id="ksktable" border="1" cellspacing="1" cellpadding="10">
    <tr>
      <th>Position</th>
      <xsl:for-each select="ksk/lists/list">
      <th class="listname"><xsl:value-of select="@n"/></th>
      </xsl:for-each>
    </tr>
    <xsl:call-template name="loopusers">
      <xsl:with-param name="startval" select="1"/>
      <xsl:with-param name="endval" select="$longest"/>
    </xsl:call-template>
  </table>
</body>
</html>
</xsl:template>
</xsl:stylesheet>
