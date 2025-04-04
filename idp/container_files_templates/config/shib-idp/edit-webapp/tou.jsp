<%@ page pageEncoding="UTF-8" %>
<%@ taglib uri="http://www.springframework.org/tags" prefix="spring" %>
<!DOCTYPE html>
<html>
 <head>
  <meta charset="utf-8">
  <title>
   <spring:message code="root.title" text="Shibboleth IdP" /> - <spring:message code="my-tou.title" text="Terms of Use" />
  </title>
  <link rel="stylesheet" type="text/css" href="<%= request.getContextPath()%>/css/consent.css">
 </head>
 
 <body>
  <div class="box">
   <header>
    <a href="<spring:message code="idp.logo.target.url" />" target="_blank">
       <img src="<%= request.getContextPath() %><spring:message code="idp.logo" />"
        alt="<spring:message code="idp.logo.alt-text" text="logo" />">
    </a>
   </header>
 
   <div id="tou-content">
    <spring:message code="my-tou.text" text="Terms of Use" />
   </div>

   <footer>
    <div class="container container-footer">
      <p class="footer-text"><spring:message code="root.footer" text="Insert your footer text in messages." /></p>
    </div>
  </footer>

  </div>
 
 </body>
</html>